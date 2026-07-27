import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'storage_service.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  GoogleSignIn? _googleSignIn;
  GoogleSignInAccount? _account;
  bool _isSyncing = false;
  String? _deviceId;
  String? _deviceName;

  static const String _driveScope =
      'https://www.googleapis.com/auth/drive.appdata';
  static const String _filePrefix = 'wispie_sync_v1_';
  static const String _webClientId =
      '80722956975-ghsnp5ldk663u7m2vmg1e6e9ajfksp0k.apps.googleusercontent.com';
  static const List<String> _syncableSettingsKeys = [
    'theme_mode',
    'use_cover_color',
    'apply_cover_color_to_all',
    'sort_order',
    'visualizer_enabled',
    'visualizer_mode',
    'show_song_duration',
    'animated_sound_wave_enabled',
    'show_waveform',
    'fade_out_duration',
    'fade_in_duration',
    'delay_duration',
    'play_fade_duration',
    'pause_fade_duration',
    'keep_screen_awake_on_lyrics',
    'cover_sizing_mode',
    'lyrics_blur_overlay_enabled',
    'beat_reactive_cover_enabled',
    'beat_reactive_particles_enabled',
    'player_motion_intensity',
    'player_motion_custom_intensity',
    'player_motion_latency_ms',
    'progressive_blur_headers',
    'show_quick_picks',
    'show_recent_queues',
    'show_for_you',
    'lyrics_target_language',
    'lyrics_auto_translate',
    'lyrics_translation_mode',
    'auto_hide_bottom_bar_on_scroll',
    'telemetry_enabled',
    'auto_pause_on_volume_zero',
    'auto_resume_on_volume_restore',
  ];

  bool get isSignedIn => _account != null;
  bool get isSyncing => _isSyncing;
  String? get accountEmail => _account?.email;
  String get deviceId => _deviceId ?? 'unknown';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('sync_device_id');
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await prefs.setString('sync_device_id', _deviceId!);
    }

    try {
      _googleSignIn = GoogleSignIn(
        scopes: [_driveScope],
        clientId: _webClientId,
      );
      _account = await _googleSignIn!.signInSilently();
    } catch (e) {
      debugPrint('SyncService: silent sign-in failed: $e');
    }
  }

  Future<bool> signIn() async {
    try {
      _googleSignIn ??=
          GoogleSignIn(scopes: [_driveScope], clientId: _webClientId);
      final account = await _googleSignIn!.signIn();
      if (account == null) return false;
      _account = account;
      return true;
    } catch (e) {
      debugPrint('SyncService: sign-in failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    _account = null;
  }

  Future<bool> sync() async {
    if (_isSyncing) return false;
    if (_account == null) return false;

    _isSyncing = true;
    try {
      final authHeaders = await _account!.authHeaders;
      final token = authHeaders['Authorization'];
      if (token == null) throw Exception('No auth token');

      final snapshot = await _composeSnapshot();
      final fileName =
          '$_filePrefix${_deviceId}_${DateTime.now().millisecondsSinceEpoch}.json';

      final processedFiles = await _getProcessedFiles();
      final existingFiles = await _listDriveFiles(token);

      for (final file in existingFiles) {
        final name = file['name'] as String? ?? '';
        if (name.startsWith(_filePrefix) && !processedFiles.contains(name)) {
          try {
            final json = await _downloadFile(token, file['id'] as String);
            await _mergeSnapshot(json);
            processedFiles.add(name);
          } catch (e) {
            debugPrint('SyncService: failed to process $name: $e');
          }
        }
      }

      await _setProcessedFiles(processedFiles);
      await _uploadSnapshot(token, fileName, snapshot);
      await _cleanupOldSnapshots(token, existingFiles);
      await _updateLastSyncTimestamp();

      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('SyncService: sync failed: $e');
      _isSyncing = false;
      return false;
    }
  }

  Future<Map<String, dynamic>> _composeSnapshot() async {
    final db = DatabaseService.instance;
    final storage = StorageService();

    final settings = await storage.exportAppSettings();
    final syncedSettings = <String, dynamic>{};
    for (final key in _syncableSettingsKeys) {
      if (settings.containsKey(key)) {
        syncedSettings[key] = settings[key];
      }
    }

    final artistArt = await db.getArtistArtForSync();
    final albumArt = await db.getAlbumArtForSync();
    final artFiles = <String, Map<String, String>>{};

    for (final a in artistArt) {
      final path = a['local_path'] as String?;
      if (path != null && await File(path).exists()) {
        try {
          final bytes = await File(path).readAsBytes();
          final hash = sha1.convert(bytes).toString();
          final ext = p.extension(path);
          artFiles[hash] = {
            'data': base64Encode(bytes),
            'mime': ext == '.png' ? 'image/png' : 'image/jpeg',
          };
          a['local_path_hash'] = hash;
        } catch (e) {
          debugPrint('SyncService: failed to read artist art: $e');
        }
      }
    }

    for (final a in albumArt) {
      final path = a['local_path'] as String?;
      if (path != null && await File(path).exists()) {
        try {
          final bytes = await File(path).readAsBytes();
          final hash = sha1.convert(bytes).toString();
          final ext = p.extension(path);
          artFiles[hash] = {
            'data': base64Encode(bytes),
            'mime': ext == '.png' ? 'image/png' : 'image/jpeg',
          };
          a['local_path_hash'] = hash;
        } catch (e) {
          debugPrint('SyncService: failed to read album art: $e');
        }
      }
    }

    return {
      'version': 1,
      'device_id': _deviceId,
      'device_name': _deviceName ?? _deviceId,
      'created_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'play_events': await db.getPlayEventsForSync(),
      'favorites': await db.getFavoritesWithTimestamps(),
      'suggestless': await db.getSuggestLessWithTimestamps(),
      'hidden': await db.getHiddenWithTimestamps(),
      'playlists': await db.getPlaylistsForSync(),
      'merged_groups': await db.getMergedGroupsForSync(),
      'settings': syncedSettings,
      'artist_art': artistArt,
      'album_art': albumArt,
      'art_files': artFiles,
    };
  }

  Future<void> _mergeSnapshot(Map<String, dynamic> snapshot) async {
    final db = DatabaseService.instance;
    final deviceId = snapshot['device_id'] as String?;

    if (deviceId == null || deviceId == _deviceId) return;

    try {
      if (snapshot['play_events'] is List) {
        final events =
            List<Map<String, dynamic>>.from(snapshot['play_events'] as List);
        await db.insertPlayEventsBatch(events);
      }
    } catch (e) {
      debugPrint('SyncService: failed to merge play events: $e');
    }

    if (snapshot['favorites'] is List) {
      await db.importFavorites(
          List<Map<String, dynamic>>.from(snapshot['favorites'] as List));
    }
    if (snapshot['suggestless'] is List) {
      await db.importSuggestLess(
          List<Map<String, dynamic>>.from(snapshot['suggestless'] as List));
    }
    if (snapshot['hidden'] is List) {
      await db.importHidden(
          List<Map<String, dynamic>>.from(snapshot['hidden'] as List));
    }
    if (snapshot['playlists'] is List) {
      await db.importPlaylists(
          List<Map<String, dynamic>>.from(snapshot['playlists'] as List));
    }
    if (snapshot['merged_groups'] is List) {
      await db.importMergedGroups(
          List<Map<String, dynamic>>.from(snapshot['merged_groups'] as List));
    }

    if (snapshot['settings'] is Map) {
      await _mergeSettings(snapshot['settings'] as Map<String, dynamic>,
          snapshot['device_id'] as String?);
    }

    if (snapshot['artist_art'] is List) {
      await _mergeArtistArtWithFiles(
        List<Map<String, dynamic>>.from(snapshot['artist_art'] as List),
        snapshot['art_files'] as Map<String, dynamic>? ?? {},
      );
    }
    if (snapshot['album_art'] is List) {
      await _mergeAlbumArtWithFiles(
        List<Map<String, dynamic>>.from(snapshot['album_art'] as List),
        snapshot['art_files'] as Map<String, dynamic>? ?? {},
      );
    }
  }

  Future<void> _mergeSettings(
      Map<String, dynamic> remoteSettings, String? remoteDeviceId) async {
    if (remoteDeviceId == null || remoteDeviceId == _deviceId) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in remoteSettings.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
  }

  Future<void> _mergeArtistArtWithFiles(
    List<Map<String, dynamic>> artistArt,
    Map<String, dynamic> artFiles,
  ) async {
    final db = DatabaseService.instance;
    final syncDir = await _getSyncArtDir();
    final updated = <Map<String, dynamic>>[];

    for (final a in artistArt) {
      final hash = a['local_path_hash'] as String?;
      if (hash != null && artFiles.containsKey(hash)) {
        final fileData = artFiles[hash] as Map<String, dynamic>;
        final data = fileData['data'] as String?;
        final mime = fileData['mime'] as String? ?? 'image/jpeg';
        if (data != null) {
          final ext = mime == 'image/png' ? '.png' : '.jpg';
          final filePath = p.join(syncDir.path, 'artist_$hash$ext');
          final file = File(filePath);
          if (!await file.exists()) {
            await file.writeAsBytes(base64Decode(data));
          }
          a['local_path'] = filePath;
        }
      }
      updated.add(a);
    }

    await db.importArtistArtBatch(updated);
  }

  Future<void> _mergeAlbumArtWithFiles(
    List<Map<String, dynamic>> albumArt,
    Map<String, dynamic> artFiles,
  ) async {
    final db = DatabaseService.instance;
    final syncDir = await _getSyncArtDir();
    final updated = <Map<String, dynamic>>[];

    for (final a in albumArt) {
      final hash = a['local_path_hash'] as String?;
      if (hash != null && artFiles.containsKey(hash)) {
        final fileData = artFiles[hash] as Map<String, dynamic>;
        final data = fileData['data'] as String?;
        final mime = fileData['mime'] as String? ?? 'image/jpeg';
        if (data != null) {
          final ext = mime == 'image/png' ? '.png' : '.jpg';
          final filePath = p.join(syncDir.path, 'album_$hash$ext');
          final file = File(filePath);
          if (!await file.exists()) {
            await file.writeAsBytes(base64Decode(data));
          }
          a['local_path'] = filePath;
        }
      }
      updated.add(a);
    }

    await db.importAlbumArtBatch(updated);
  }

  Future<Directory> _getSyncArtDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'sync_art'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Map<String, dynamic>>> _listDriveFiles(String token) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder&q=name%20contains%20%27$_filePrefix%27'
      '&fields=files(id%2Cname%2CcreatedTime)',
    );
    try {
      final response = await http.get(url, headers: {
        'Authorization': token,
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(data['files'] as List? ?? []);
      }
    } catch (e) {
      debugPrint('SyncService: list files failed: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> _downloadFile(
      String token, String fileId) async {
    final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final response = await http.get(url, headers: {
      'Authorization': token,
    });
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Download failed: ${response.statusCode}');
  }

  Future<void> _uploadSnapshot(
      String token, String fileName, Map<String, dynamic> snapshot) async {
    final metadata = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
    });
    final body = jsonEncode(snapshot);

    final boundary = 'Boundary_${DateTime.now().millisecondsSinceEpoch}';
    final bodyBytes = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/json\r\n\r\n'
      '$body\r\n'
      '--$boundary--\r\n',
    );

    final url = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
    final response = await http.post(
      url,
      headers: {
        'Authorization': token,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: bodyBytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
          'SyncService: upload failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> _deleteFile(String token, String fileId) async {
    final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
    try {
      await http.delete(url, headers: {
        'Authorization': token,
      });
    } catch (e) {
      debugPrint('SyncService: delete failed: $e');
    }
  }

  Future<void> _cleanupOldSnapshots(
      String token, List<Map<String, dynamic>> files) async {
    final ourPrefix = '$_filePrefix${_deviceId}_';
    final ourFiles = files.where((f) {
      final name = f['name'] as String? ?? '';
      return name.startsWith(ourPrefix);
    }).toList();

    if (ourFiles.length <= 1) return;

    ourFiles.sort((a, b) {
      final aTime = a['createdTime'] as String? ?? '';
      final bTime = b['createdTime'] as String? ?? '';
      return bTime.compareTo(aTime);
    });

    for (int i = 1; i < ourFiles.length; i++) {
      await _deleteFile(token, ourFiles[i]['id'] as String);
    }
  }

  Future<void> _updateLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
        'sync_last_timestamp', DateTime.now().millisecondsSinceEpoch / 1000.0);
  }

  Future<Set<String>> _getProcessedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('sync_processed_files')?.toSet() ?? {};
  }

  Future<void> _setProcessedFiles(Set<String> files) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sync_processed_files', files.toList());
  }

  Future<double?> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getDouble('sync_last_timestamp');
    return ts;
  }

  String _generateDeviceId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return sha1.convert(bytes).toString().substring(0, 12);
  }
}

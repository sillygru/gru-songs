import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'google_oauth_service.dart';
import 'storage_service.dart';

typedef SyncProgressCallback = void Function(
    String statusMessage, double progress);

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  final GoogleOAuthService _oauth = GoogleOAuthService();
  bool _isSyncing = false;
  String? _deviceId;
  String? _deviceName;

  static const String _filePrefix = 'wispie_sync_v1_';
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

  bool get isSignedIn => _oauth.isSignedIn;
  bool get isSyncing => _isSyncing;
  String? get accountEmail => _oauth.accountEmail;
  String? get lastError => _oauth.lastError;
  String get deviceId {
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('sync_device_id', _deviceId!);
      });
    }
    return _deviceId!;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('sync_device_id');
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await prefs.setString('sync_device_id', _deviceId!);
    }

    try {
      await _oauth.init();
    } catch (e) {
      debugPrint('SyncService: OAuth init failed: $e');
    }
  }

  Future<bool> signIn() async {
    return await _oauth.signIn();
  }

  Future<void> signOut() async {
    await _oauth.signOut();
  }

  Future<bool> sync(
      {SyncProgressCallback? onProgress, bool syncSettings = true}) async {
    if (_isSyncing) return false;
    if (!_oauth.isSignedIn) return false;

    _isSyncing = true;
    try {
      onProgress?.call('Connecting to Google Drive...', 0.1);
      final authHeaders = await _oauth.authHeaders;
      final token = authHeaders['Authorization'];
      if (token == null) throw Exception('No auth token');

      onProgress?.call('Preparing local snapshot...', 0.2);
      final snapshot = await _composeSnapshot(syncSettings: syncSettings);
      final fileName =
          '$_filePrefix${_deviceId}_${DateTime.now().millisecondsSinceEpoch}.json';

      onProgress?.call('Listing cloud backups...', 0.3);
      final processedFiles = await _getProcessedFiles();
      final existingFiles = await _listDriveFiles(token);

      int remoteCount = 0;
      for (final file in existingFiles) {
        final name = file['name'] as String? ?? '';
        if (name.startsWith(_filePrefix) && !processedFiles.contains(name)) {
          remoteCount++;
        }
      }

      int processedCount = 0;
      for (final file in existingFiles) {
        final name = file['name'] as String? ?? '';
        if (name.startsWith(_filePrefix) && !processedFiles.contains(name)) {
          try {
            processedCount++;
            onProgress?.call(
                'Downloading snapshot ($processedCount/$remoteCount)...', 0.4);
            final json = await _downloadFile(token, file['id'] as String);
            await _mergeSnapshot(json,
                syncSettings: syncSettings, onProgress: onProgress);
            processedFiles.add(name);
          } catch (e) {
            debugPrint('SyncService: failed to process $name: $e');
          }
        }
      }

      await _setProcessedFiles(processedFiles);
      onProgress?.call('Uploading snapshot to cloud...', 0.8);
      await _uploadSnapshot(token, fileName, snapshot);
      onProgress?.call('Cleaning up old snapshots...', 0.95);
      await _cleanupOldSnapshots(token, existingFiles);
      await _updateLastSyncTimestamp();

      onProgress?.call('Sync complete', 1.0);
      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('SyncService: sync failed: $e');
      _isSyncing = false;
      return false;
    }
  }

  Future<bool> forcePushLocalToCloud(
      {SyncProgressCallback? onProgress, bool syncSettings = true}) async {
    if (_isSyncing) return false;
    if (!_oauth.isSignedIn) return false;

    _isSyncing = true;
    try {
      onProgress?.call('Connecting to Google Drive...', 0.1);
      final authHeaders = await _oauth.authHeaders;
      final token = authHeaders['Authorization'];
      if (token == null) throw Exception('No auth token');

      onProgress?.call('Listing cloud backups...', 0.25);
      final existingFiles = await _listDriveFiles(token);

      onProgress?.call('Removing old cloud snapshots...', 0.4);
      for (final file in existingFiles) {
        final name = file['name'] as String? ?? '';
        if (name.startsWith(_filePrefix)) {
          await _deleteFile(token, file['id'] as String);
        }
      }

      onProgress?.call('Preparing local snapshot...', 0.65);
      final snapshot = await _composeSnapshot(syncSettings: syncSettings);
      final fileName =
          '$_filePrefix${_deviceId}_${DateTime.now().millisecondsSinceEpoch}.json';

      onProgress?.call('Uploading fresh snapshot...', 0.85);
      await _uploadSnapshot(token, fileName, snapshot);
      await _setProcessedFiles({fileName});
      await _updateLastSyncTimestamp();

      onProgress?.call('Cloud updated with local data', 1.0);
      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('SyncService: force push failed: $e');
      _isSyncing = false;
      return false;
    }
  }

  Future<bool> forcePullCloudToLocal(
      {SyncProgressCallback? onProgress, bool syncSettings = true}) async {
    if (_isSyncing) return false;
    if (!_oauth.isSignedIn) return false;

    _isSyncing = true;
    try {
      onProgress?.call('Connecting to Google Drive...', 0.1);
      final authHeaders = await _oauth.authHeaders;
      final token = authHeaders['Authorization'];
      if (token == null) throw Exception('No auth token');

      onProgress?.call('Fetching cloud backups...', 0.25);
      final existingFiles = await _listDriveFiles(token);
      final validFiles = existingFiles.where((f) {
        final name = f['name'] as String? ?? '';
        return name.startsWith(_filePrefix);
      }).toList();

      if (validFiles.isEmpty) {
        throw Exception('No cloud backups found');
      }

      validFiles.sort((a, b) {
        final aTime = a['createdTime'] as String? ?? '';
        final bTime = b['createdTime'] as String? ?? '';
        return bTime.compareTo(aTime);
      });

      onProgress?.call('Downloading cloud snapshots...', 0.5);
      onProgress?.call('Clearing local play stats...', 0.7);
      await DatabaseService.instance.clearAllPlayStats();

      onProgress?.call('Importing cloud stats...', 0.85);
      for (final file in validFiles) {
        try {
          final snapshot = await _downloadFile(token, file['id'] as String);
          await _mergeSnapshot(
            snapshot,
            syncSettings: syncSettings,
            forceImport: true,
            onProgress: onProgress,
          );
        } catch (e) {
          debugPrint(
              'SyncService: force pull failed to process ${file['name']}: $e');
        }
      }

      final processedFiles = validFiles.map((f) => f['name'] as String).toSet();
      await _setProcessedFiles(processedFiles);
      await _updateLastSyncTimestamp();

      onProgress?.call('Local data replaced from cloud', 1.0);
      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('SyncService: force pull failed: $e');
      _isSyncing = false;
      return false;
    }
  }

  Future<Map<String, dynamic>> _composeSnapshot(
      {bool syncSettings = true}) async {
    final db = DatabaseService.instance;
    final storage = StorageService();

    final syncedSettings = <String, dynamic>{};
    if (syncSettings) {
      final settings = await storage.exportAppSettings();
      for (final key in _syncableSettingsKeys) {
        if (settings.containsKey(key)) {
          syncedSettings[key] = settings[key];
        }
      }
    }

    final artistArt = await db.getArtistArtForSync();
    final albumArt = await db.getAlbumArtForSync();

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
    };
  }

  Future<void> _mergeSnapshot(
    Map<String, dynamic> snapshot, {
    bool syncSettings = true,
    bool forceImport = false,
    SyncProgressCallback? onProgress,
  }) async {
    final db = DatabaseService.instance;
    final deviceId = snapshot['device_id'] as String?;

    if (!forceImport && (deviceId == null || deviceId == _deviceId)) return;

    try {
      if (snapshot['play_events'] is List) {
        onProgress?.call('Merging play stats...', 0.45);
        final events =
            List<Map<String, dynamic>>.from(snapshot['play_events'] as List);
        for (final ev in events) {
          final evDevId = ev['device_id'] as String?;
          if ((evDevId == null || evDevId.isEmpty) &&
              deviceId != null &&
              deviceId.isNotEmpty) {
            ev['device_id'] = deviceId;
          }
        }
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
      onProgress?.call('Merging playlists...', 0.6);
      await db.importPlaylists(
          List<Map<String, dynamic>>.from(snapshot['playlists'] as List));
    }
    if (snapshot['merged_groups'] is List) {
      await db.importMergedGroups(
          List<Map<String, dynamic>>.from(snapshot['merged_groups'] as List));
    }

    if (syncSettings && snapshot['settings'] is Map) {
      onProgress?.call('Merging settings...', 0.7);
      await _mergeSettings(snapshot['settings'] as Map<String, dynamic>,
          snapshot['device_id'] as String?);
    }

    if (snapshot['artist_art'] is List) {
      await db.importArtistArtBatch(
          List<Map<String, dynamic>>.from(snapshot['artist_art'] as List));
    }
    if (snapshot['album_art'] is List) {
      await db.importAlbumArtBatch(
          List<Map<String, dynamic>>.from(snapshot['album_art'] as List));
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
      final body = response.body;
      return await Isolate.run(() => jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Download failed: ${response.statusCode}');
  }

  Future<void> _uploadSnapshot(
      String token, String fileName, Map<String, dynamic> snapshot) async {
    final metadata = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
    });

    final boundary = 'Boundary_${DateTime.now().millisecondsSinceEpoch}';
    final bodyBytes = await Isolate.run(() {
      final body = jsonEncode(snapshot);
      return utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$body\r\n'
        '--$boundary--\r\n',
      );
    });

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

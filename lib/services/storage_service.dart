import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'android_storage_service.dart';
import 'cache_service.dart';
import 'ios_folder_access_service.dart';
import 'import_options.dart';

class StorageService {
  static const String _musicFoldersKey = 'music_folders_list';
  static const String _musicFolderKey = 'music_folder_path';
  static const String _excludedFoldersKey = 'excluded_folders';
  static const String _lastLibraryFolderKey = 'last_library_folder';
  static const String _isSetupCompleteKey = 'is_setup_complete_v2';
  static const String _isLocalModeKey = 'is_local_mode';
  static const String _localUsernameKey = 'local_username';
  static const String _pullToRefreshEnabledKey = 'pull_to_refresh_enabled';
  static const String _telemetryLevelKey = 'telemetry_level';
  static const String _hasSentFirstStartupKey = 'has_sent_first_startup';

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> getSongsFile() async {
    final path = await _localPath;
    return File('$path/cached_songs.json');
  }

  Future<File> _getUserDataFile() async {
    final path = await _localPath;
    return File('$path/user_data.json');
  }

  Future<File> _getShuffleStateFile() async {
    final path = await _localPath;
    return File('$path/shuffle_state.json');
  }

  Future<File> _getPlaybackStateFile() async {
    final path = await _localPath;
    return File('$path/playback_state.json');
  }

  List<Map<String, String>>? _cachedMusicFolders;

  Map<String, String> _normalizeFolderRecord(Map<String, String> folder) {
    return {
      'path': folder['path'] ?? '',
      'treeUri': folder['treeUri'] ?? '',
      'platform': folder['platform'] ??
          (Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
                  ? 'android'
                  : Platform.operatingSystem),
      'iosBookmarkId': folder['iosBookmarkId'] ?? '',
    };
  }

  Map<String, String> _decodeFolderRecord(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return _normalizeFolderRecord({'path': ''});
    }

    if (!trimmed.startsWith('{')) {
      return _normalizeFolderRecord({'path': trimmed});
    }

    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      return _normalizeFolderRecord({
        'path': map['path'] as String? ?? '',
        'treeUri': map['treeUri'] as String? ?? '',
        'platform': map['platform'] as String? ?? '',
        'iosBookmarkId': map['iosBookmarkId'] as String? ?? '',
      });
    } catch (_) {
      return _normalizeFolderRecord({'path': trimmed});
    }
  }

  List<String> _encodeFolderRecords(List<Map<String, String>> folders) {
    return folders.map((folder) {
      final normalized = _normalizeFolderRecord(folder);
      return jsonEncode(normalized);
    }).toList(growable: false);
  }

  Future<void> _persistMusicFolders(List<Map<String, String>> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_musicFoldersKey, _encodeFolderRecords(folders));
    _cachedMusicFolders = folders.map(_normalizeFolderRecord).toList();
  }

  Future<void> _markLibraryFoldersChanged() async {
    await CacheService.instance.markLibraryChanged();
  }

  Future<Map<String, String>?> pickMusicFolder() async {
    if (Platform.isAndroid) {
      final selection = await AndroidStorageService.pickTree();
      if (selection == null ||
          selection.path == null ||
          selection.path!.isEmpty) {
        return null;
      }

      return _normalizeFolderRecord({
        'path': selection.path!,
        'treeUri': selection.treeUri,
        'platform': 'android',
      });
    }

    if (Platform.isIOS) {
      final selection = await IosFolderAccessService.pickFolder();
      if (selection == null ||
          selection.path.isEmpty ||
          selection.bookmarkId.isEmpty) {
        return null;
      }

      return _normalizeFolderRecord({
        'path': selection.path,
        'platform': 'ios',
        'iosBookmarkId': selection.bookmarkId,
      });
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null || selectedDirectory.isEmpty) return null;
    return _normalizeFolderRecord({
      'path': selectedDirectory,
      'platform': Platform.operatingSystem,
    });
  }

  Future<void> savePlaybackState(Map<String, dynamic> state) async {
    try {
      final file = await _getPlaybackStateFile();
      await file.writeAsString(jsonEncode(state));
    } catch (e) {
      debugPrint('Error saving playback state: $e');
    }
  }

  Future<Map<String, dynamic>?> loadPlaybackState() async {
    try {
      final file = await _getPlaybackStateFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading playback state: $e');
      return null;
    }
  }

  // Multiple Music Folders
  Future<List<Map<String, String>>> getMusicFolders(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMusicFolders != null) {
      return _cachedMusicFolders!.map(_normalizeFolderRecord).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_musicFoldersKey) ?? [];
    final decodedFromPrefs = jsonList.map(_decodeFolderRecord).toList();

    if (Platform.isIOS) {
      final resolved = await IosFolderAccessService.loadResolvedFolders();
      if (resolved.isNotEmpty) {
        final normalized = resolved.map(_normalizeFolderRecord).toList();
        await _persistMusicFolders(normalized);
        return normalized;
      }
    }

    if (decodedFromPrefs.isNotEmpty) {
      _cachedMusicFolders = decodedFromPrefs;
      return decodedFromPrefs.map(_normalizeFolderRecord).toList();
    }

    if (Platform.isIOS) {
      final restored = await IosFolderAccessService.loadPersistedFolders();
      if (restored.isNotEmpty) {
        final normalized = restored.map(_normalizeFolderRecord).toList();
        await _persistMusicFolders(normalized);
        return normalized;
      }
    }

    _cachedMusicFolders = decodedFromPrefs;
    return decodedFromPrefs.map(_normalizeFolderRecord).toList();
  }

  Future<void> setMusicFolders(List<Map<String, String>> folders) async {
    final normalized = folders.map(_normalizeFolderRecord).toList();
    await _persistMusicFolders(normalized);
    await _markLibraryFoldersChanged();
  }

  Future<void> addMusicFolder(
    String path,
    String? treeUri, {
    String? iosBookmarkId,
    String? platform,
  }) async {
    final current = await getMusicFolders(forceRefresh: true);
    final next = List<Map<String, String>>.from(current);
    final normalized = _normalizeFolderRecord({
      'path': path,
      'treeUri': treeUri ?? '',
      'platform': platform ??
          (Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
                  ? 'android'
                  : Platform.operatingSystem),
      'iosBookmarkId': iosBookmarkId ?? '',
    });

    final existingIndex = next.indexWhere((folder) =>
        folder['path'] == normalized['path'] ||
        (normalized['iosBookmarkId']?.isNotEmpty == true &&
            folder['iosBookmarkId'] == normalized['iosBookmarkId']));
    if (existingIndex >= 0) {
      next[existingIndex] = normalized;
    } else {
      next.add(normalized);
    }

    await _persistMusicFolders(next);
    await _markLibraryFoldersChanged();
  }

  Future<void> removeMusicFolder(String path, {String? iosBookmarkId}) async {
    final current = await getMusicFolders(forceRefresh: true);
    final target = current.where((folder) {
      if (iosBookmarkId != null && iosBookmarkId.isNotEmpty) {
        return folder['iosBookmarkId'] == iosBookmarkId;
      }
      return folder['path'] == path;
    }).toList();

    if (Platform.isIOS) {
      for (final folder in target) {
        final bookmarkId = folder['iosBookmarkId'];
        if (bookmarkId != null && bookmarkId.isNotEmpty) {
          await IosFolderAccessService.removeFolder(bookmarkId);
        }
      }
    }

    final remaining = current.where((folder) {
      if (iosBookmarkId != null && iosBookmarkId.isNotEmpty) {
        return folder['iosBookmarkId'] != iosBookmarkId;
      }
      return folder['path'] != path;
    }).toList();

    await _persistMusicFolders(remaining);
    await _markLibraryFoldersChanged();
  }

  // Legacy compatibility - returns first music folder or null
  Future<String?> getMusicFolderPath() async {
    final folders = await getMusicFolders();
    if (folders.isNotEmpty) {
      return folders.first['path'];
    }
    // Fallback to old key for migration
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_musicFolderKey);
  }

  Future<bool> getIsSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isSetupCompleteKey) ?? false;
  }

  Future<void> setSetupComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isSetupCompleteKey, value);
  }

  Future<bool> getIsLocalMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLocalModeKey) ?? false;
  }

  Future<void> setIsLocalMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLocalModeKey, value);
  }

  Future<String?> getLocalUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localUsernameKey);
  }

  Future<void> setLocalUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localUsernameKey, username);
  }

  Future<bool> getPullToRefreshEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pullToRefreshEnabledKey) ?? true;
  }

  Future<void> setPullToRefreshEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pullToRefreshEnabledKey, value);
  }

  Future<int> getTelemetryLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_telemetryLevelKey) ?? 1; // Default to level 1
  }

  Future<void> setTelemetryLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_telemetryLevelKey, level);
  }

  Future<bool> getHasSentFirstStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSentFirstStartupKey) ?? false;
  }

  Future<void> setHasSentFirstStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSentFirstStartupKey, value);
  }

  // Excluded Folders
  Future<List<String>> getExcludedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_excludedFoldersKey) ?? [];
  }

  Future<void> setExcludedFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_excludedFoldersKey, folders);
  }

  Future<void> addExcludedFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_excludedFoldersKey) ?? [];
    if (!current.contains(folder)) {
      current.add(folder);
      await prefs.setStringList(_excludedFoldersKey, current);
    }
  }

  Future<void> removeExcludedFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_excludedFoldersKey) ?? [];
    current.remove(folder);
    await prefs.setStringList(_excludedFoldersKey, current);
  }

  // Last Library Folder
  Future<String?> getLastLibraryFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastLibraryFolderKey);
  }

  Future<void> setLastLibraryFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLibraryFolderKey, folder);
  }

  Future<void> saveUserData(Map<String, dynamic> data) async {
    try {
      final file = await _getUserDataFile();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving user data cache: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserData() async {
    try {
      final file = await _getUserDataFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading user data cache: $e');
      return null;
    }
  }

  Future<void> saveShuffleState(Map<String, dynamic> state) async {
    try {
      final file = await _getShuffleStateFile();
      await file.writeAsString(jsonEncode(state));
    } catch (e) {
      debugPrint('Error saving shuffle state: $e');
    }
  }

  Future<Map<String, dynamic>?> loadShuffleState() async {
    try {
      final file = await _getShuffleStateFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading shuffle state: $e');
      return null;
    }
  }

  static const List<String> _settingsKeys = [
    'theme_mode',
    'use_cover_color',
    'apply_cover_color_to_all',
    'username',
    'local_username',
    'music_folders_list',
    'excluded_folders',
    'last_library_folder',
    'is_local_mode',
    'is_setup_complete_v2',
    'sort_order',
    'visualizer_enabled',
    'auto_hide_bottom_bar_on_scroll',
    'pull_to_refresh_enabled',
    'telemetry_level',
    'has_sent_first_startup',
    'auto_pause_on_volume_zero',
    'auto_resume_on_volume_restore',
    'show_song_duration',
    'animated_sound_wave_enabled',
    'show_waveform',
    'fade_out_duration',
    'fade_in_duration',
    'delay_duration',
    'quick_action_config',
    'auto_backup_frequency_hours',
    'auto_backup_delete_after_days',
    'prevent_duplicate_tracks',
    'prevent_merged_duplicates',
    'extract_feat_artists',
    'minimum_file_size_bytes',
    'minimum_track_duration_ms',
    'include_videos',
    'play_fade_duration',
    'pause_fade_duration',
    'keep_screen_awake_on_lyrics',
    'cover_sizing_mode',
    'gap_song_id',
    'gap_resume_timestamp',
    'gap_is_active',
  ];

  Future<Map<String, dynamic>> exportAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final result = <String, dynamic>{};

    for (final key in _settingsKeys) {
      if (allKeys.contains(key)) {
        final value = prefs.get(key);
        if (value != null) {
          result[key] = value;
        }
      }
    }

    for (final key in allKeys) {
      if (!result.containsKey(key)) {
        final value = prefs.get(key);
        if (value != null) {
          result[key] = value;
        }
      }
    }

    return result;
  }

  Future<void> importAppSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();

    for (final entry in settings.entries) {
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

  Future<void> importSettingsWithOptions(
    Map<String, dynamic> allSettings,
    ImportOptions options,
  ) async {
    final categories = options.categories;

    if (categories.contains(ImportDataCategory.themeSettings)) {
      await importThemeSettings(allSettings);
    }
    if (categories.contains(ImportDataCategory.scannerSettings)) {
      await importScannerSettings(allSettings);
    }
    if (categories.contains(ImportDataCategory.playbackSettings)) {
      await importPlaybackSettings(allSettings);
    }
    if (categories.contains(ImportDataCategory.uiSettings)) {
      await importUISettings(allSettings);
    }
    if (categories.contains(ImportDataCategory.backupSettings)) {
      await importBackupSettings(allSettings);
    }
  }

  static const List<String> _themeSettingsKeys = [
    'theme_mode',
    'use_cover_color',
    'apply_cover_color_to_all',
  ];

  static const List<String> _scannerSettingsKeys = [
    'music_folders_list',
    'excluded_folders',
    'last_library_folder',
    'minimum_file_size_bytes',
    'minimum_track_duration_ms',
    'include_videos',
  ];

  static const List<String> _playbackSettingsKeys = [
    'play_fade_duration',
    'pause_fade_duration',
    'gap_song_id',
    'gap_resume_timestamp',
    'gap_is_active',
  ];

  static const List<String> _uiSettingsKeys = [
    'sort_order',
    'visualizer_enabled',
    'auto_hide_bottom_bar_on_scroll',
    'show_song_duration',
    'animated_sound_wave_enabled',
    'show_waveform',
    'quick_action_config',
    'cover_sizing_mode',
    'pull_to_refresh_enabled',
  ];

  static const List<String> _backupSettingsKeys = [
    'auto_backup_frequency_hours',
    'auto_backup_delete_after_days',
  ];

  Future<void> importThemeSettings(Map<String, dynamic> settings) async {
    await _importSettingsSubset(settings, _themeSettingsKeys);
  }

  Future<void> importScannerSettings(Map<String, dynamic> settings) async {
    await _importSettingsSubset(settings, _scannerSettingsKeys);
    if (settings.containsKey('music_folders_list')) {
      await CacheService.instance.markLibraryChanged();
    }
  }

  Future<void> importPlaybackSettings(Map<String, dynamic> settings) async {
    await _importSettingsSubset(settings, _playbackSettingsKeys);
  }

  Future<void> importUISettings(Map<String, dynamic> settings) async {
    await _importSettingsSubset(settings, _uiSettingsKeys);
  }

  Future<void> importBackupSettings(Map<String, dynamic> settings) async {
    await _importSettingsSubset(settings, _backupSettingsKeys);
  }

  Future<void> _importSettingsSubset(
    Map<String, dynamic> settings,
    List<String> keys,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    for (final key in keys) {
      if (settings.containsKey(key)) {
        final value = settings[key];
        if (value == null) continue;

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
  }
}

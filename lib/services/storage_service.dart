import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
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
  Future<List<Map<String, String>>> getMusicFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('music_folders_list') ?? [];
    return jsonList.map((json) {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return {
        'path': map['path'] as String,
        'treeUri': map['treeUri'] as String? ?? '',
      };
    }).toList();
  }

  Future<void> setMusicFolders(List<Map<String, String>> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = folders.map((folder) {
      return jsonEncode({
        'path': folder['path'],
        'treeUri': folder['treeUri'] ?? '',
      });
    }).toList();
    await prefs.setStringList('music_folders_list', jsonList);
  }

  Future<void> addMusicFolder(String path, String? treeUri) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList('music_folders_list') ?? [];
    final newFolder = jsonEncode({
      'path': path,
      'treeUri': treeUri ?? '',
    });
    // Check if already exists
    final exists = current.any((json) {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map['path'] == path;
    });
    if (!exists) {
      current.add(newFolder);
      await prefs.setStringList('music_folders_list', current);
    }
  }

  Future<void> removeMusicFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList('music_folders_list') ?? [];
    current.removeWhere((json) {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map['path'] == path;
    });
    await prefs.setStringList('music_folders_list', current);
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
    'sort_order',
    'visualizer_enabled',
    'auto_hide_bottom_bar_on_scroll',
    'telemetry_level',
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
}

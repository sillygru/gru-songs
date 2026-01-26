import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class StorageService {
  static const String _musicFolderKey = 'music_folder_path';
  static const String _musicFolderTreeUriKey = 'music_folder_tree_uri';
  static const String _lyricsFolderKey = 'lyrics_folder_path';
  static const String _lyricsFolderTreeUriKey = 'lyrics_folder_tree_uri';
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

  Future<File> _getSongsFile(String? username) async {
    final path = await _localPath;
    final suffix = username != null ? '_$username' : '';
    return File('$path/cached_songs$suffix.json');
  }

  Future<File> _getUserDataFile(String username) async {
    final path = await _localPath;
    return File('$path/user_data_$username.json');
  }

  Future<File> _getShuffleStateFile(String username) async {
    final path = await _localPath;
    return File('$path/shuffle_state_$username.json');
  }

  Future<File> _getPlaybackStateFile(String username) async {
    final path = await _localPath;
    return File('$path/playback_state_$username.json');
  }

  Future<void> savePlaybackState(
      String username, Map<String, dynamic> state) async {
    try {
      final file = await _getPlaybackStateFile(username);
      await file.writeAsString(jsonEncode(state));
    } catch (e) {
      debugPrint('Error saving playback state: $e');
    }
  }

  Future<Map<String, dynamic>?> loadPlaybackState(String username) async {
    try {
      final file = await _getPlaybackStateFile(username);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading playback state: $e');
      return null;
    }
  }

  // Folder Paths
  Future<String?> getMusicFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_musicFolderKey);
  }

  Future<void> setMusicFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_musicFolderKey, path);
  }

  Future<String?> getMusicFolderTreeUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_musicFolderTreeUriKey);
  }

  Future<void> setMusicFolderTreeUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_musicFolderTreeUriKey, uri);
  }

  Future<String?> getLyricsFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lyricsFolderKey);
  }

  Future<void> setLyricsFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lyricsFolderKey, path);
  }

  Future<String?> getLyricsFolderTreeUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lyricsFolderTreeUriKey);
  }

  Future<void> setLyricsFolderTreeUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lyricsFolderTreeUriKey, uri);
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

  Future<void> saveSongs(String? username, List<Song> songs) async {
    try {
      final file = await _getSongsFile(username);
      final jsonList = songs.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // Ignore errors during cache write
      debugPrint('Error saving songs cache: $e');
    }
  }

  Future<List<Song>> loadSongs(String? username) async {
    try {
      final file = await _getSongsFile(username);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) => Song.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading songs cache: $e');
      return [];
    }
  }

  Future<void> saveUserData(String username, Map<String, dynamic> data) async {
    try {
      final file = await _getUserDataFile(username);
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving user data cache: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserData(String username) async {
    try {
      final file = await _getUserDataFile(username);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading user data cache: $e');
      return null;
    }
  }

  Future<void> saveShuffleState(
      String username, Map<String, dynamic> state) async {
    try {
      final file = await _getShuffleStateFile(username);
      await file.writeAsString(jsonEncode(state));
    } catch (e) {
      debugPrint('Error saving shuffle state: $e');
    }
  }

  Future<Map<String, dynamic>?> loadShuffleState(String username) async {
    try {
      final file = await _getShuffleStateFile(username);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      debugPrint('Error loading shuffle state: $e');
      return null;
    }
  }
}

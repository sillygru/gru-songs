import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';

class StorageService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _songsFile async {
    final path = await _localPath;
    return File('$path/cached_songs.json');
  }

  Future<File> _getUserDataFile(String username) async {
    final path = await _localPath;
    return File('$path/user_data_$username.json');
  }

  Future<File> _getShuffleStateFile(String username) async {
    final path = await _localPath;
    return File('$path/shuffle_state_$username.json');
  }

  Future<File> get _syncHashesFile async {
    final path = await _localPath;
    return File('$path/sync_hashes.json');
  }

  Future<void> saveShuffleState(String username, Map<String, dynamic> state) async {
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

  Future<void> saveSongs(List<Song> songs) async {
    try {
      final file = await _songsFile;
      final jsonList = songs.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // Ignore errors during cache write
      debugPrint('Error saving songs cache: $e');
    }
  }

  Future<List<Song>> loadSongs() async {
    try {
      final file = await _songsFile;
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

  Future<void> saveSyncHashes(Map<String, String> hashes) async {
    try {
      final file = await _syncHashesFile;
      await file.writeAsString(jsonEncode(hashes));
    } catch (e) {
      debugPrint('Error saving sync hashes: $e');
    }
  }

  Future<Map<String, String>> loadSyncHashes() async {
    try {
      final file = await _syncHashesFile;
      if (!await file.exists()) return {};
      
      final content = await file.readAsString();
      return Map<String, String>.from(jsonDecode(content));
    } catch (e) {
      debugPrint('Error loading sync hashes: $e');
      return {};
    }
  }
}

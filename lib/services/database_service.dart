import 'dart:io';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  Database? _statsDatabase;
  Database? _userDataDatabase;
  String? _currentUsername;
  Completer<void>? _initCompleter;

  DatabaseService._init();

  Future<void> initForUser(String username) async {
    if (_currentUsername == username && _statsDatabase != null) return;
    
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }
    
    _initCompleter = Completer<void>();
    _currentUsername = username;
    
    try {
      // 1. If local files don't exist, try to download them immediately
      // This ensures a new device gets the user's history right away.
      await _mirrorDbsIfMissing(username);
      
      // 2. Open (and create schema if still missing after download attempt)
      _statsDatabase = await _openDatabase('${username}_stats.db', _statsSchema);
      _userDataDatabase = await _openDatabase('${username}_data.db', _userDataSchema);
      
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('Database initialization failed: $e');
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initCompleter == null) {
      throw Exception('DatabaseService not initialized. Call initForUser first.');
    }
    return _initCompleter!.future;
  }

  Future<Database> _openDatabase(String name, String schema) async {
    final docDir = await getApplicationDocumentsDirectory();
    final path = join(docDir.path, name);
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Execute multi-statement schema
        for (final statement in schema.split(';')) {
          if (statement.trim().isNotEmpty) {
            await db.execute(statement);
          }
        }
      },
    );
  }

  Future<void> _mirrorDbsIfMissing(String username) async {
    final docDir = await getApplicationDocumentsDirectory();
    final statsFile = File(join(docDir.path, '${username}_stats.db'));
    
    // Only download on first init if local files are missing
    // or if we want to force a sync (can be expanded later)
    if (!await statsFile.exists()) {
      await _downloadDb(username, 'stats');
      await _downloadDb(username, 'data');
      await _downloadDb(username, 'final_stats');
    }
  }

  Future<void> _downloadDb(String username, String type) async {
    final docDir = await getApplicationDocumentsDirectory();
    final ext = type == 'final_stats' ? 'json' : 'db';
    final filename = '${username}_$type.$ext';
    final path = join(docDir.path, filename);

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/user/db/$type'),
        headers: {'x-username': username},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final file = File(path);
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      debugPrint('Initial download of $type DB failed (Offline?): $e');
    }
  }

  Future<void> sync(String username) async {
    await _ensureInitialized();
    
    // 1. Upload local data to server for merging
    await _uploadDb(username, 'stats');
    await _uploadDb(username, 'data');
    await _uploadDb(username, 'final_stats');

    // 2. Close current connections to allow file replacement
    await _statsDatabase?.close();
    await _userDataDatabase?.close();
    _statsDatabase = null;
    _userDataDatabase = null;

    // 3. Download the merged versions from the server
    await _downloadDb(username, 'stats');
    await _downloadDb(username, 'data');
    await _downloadDb(username, 'final_stats');

    // 4. Re-open databases
    _statsDatabase = await _openDatabase('${username}_stats.db', _statsSchema);
    _userDataDatabase = await _openDatabase('${username}_data.db', _userDataSchema);
  }

  Future<void> syncBack(String username) async {
    // Push local mirrored files to server (background periodic sync)
    await _uploadDb(username, 'stats');
    await _uploadDb(username, 'data');
    await _uploadDb(username, 'final_stats');
  }

  Future<void> _uploadDb(String username, String type) async {
    final docDir = await getApplicationDocumentsDirectory();
    final ext = type == 'final_stats' ? 'json' : 'db';
    final filename = '${username}_$type.$ext';
    final path = join(docDir.path, filename);
    final file = File(path);

    if (!await file.exists()) return;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/user/db/$type'),
      );
      request.headers['x-username'] = username;
      request.files.add(await http.MultipartFile.fromPath('file', path));

      final response = await request.send().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        debugPrint('Synced $type DB to server');
      }
    } catch (e) {
      debugPrint('Sync failed for $type DB: $e');
    }
  }

  // --- User Data Queries ---

  Future<List<String>> getFavorites() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.query('favorite');
    return results.map((r) => r['filename'] as String).toList();
  }

  Future<void> addFavorite(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'favorite',
      {'filename': filename, 'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.delete('favorite', where: 'filename = ?', whereArgs: [filename]);
  }

  Future<List<String>> getSuggestLess() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.query('suggestless');
    return results.map((r) => r['filename'] as String).toList();
  }

  Future<void> addSuggestLess(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'suggestless',
      {'filename': filename, 'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeSuggestLess(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.delete('suggestless', where: 'filename = ?', whereArgs: [filename]);
  }

  // --- Playback Queries ---

  Future<Map<String, int>> getPlayCounts() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return {};
    try {
      final results = await _statsDatabase!.rawQuery(
        'SELECT song_filename, COUNT(*) as count FROM playevent WHERE play_ratio > 0.25 GROUP BY song_filename'
      );
      return {
        for (var r in results) r['song_filename'] as String: r['count'] as int
      };
    } catch (e) {
      debugPrint('Error fetching play counts: $e');
      return {};
    }
  }

  Future<void> insertPlayEvent(Map<String, dynamic> event) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;
    
    await _statsDatabase!.transaction((txn) async {
      await txn.insert('playsession', {
        'id': event['session_id'],
        'start_time': event['timestamp'],
        'end_time': event['timestamp'],
        'platform': event['platform'] ?? 'unknown',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      
      await txn.rawUpdate(
        'UPDATE playsession SET end_time = ? WHERE id = ? AND end_time < ?',
        [event['timestamp'], event['session_id'], event['timestamp']]
      );

      await txn.insert('playevent', {
        'session_id': event['session_id'],
        'song_filename': event['song_filename'],
        'event_type': event['event_type'],
        'timestamp': event['timestamp'],
        'duration_played': event['duration_played'],
        'total_length': event['total_length'],
        'play_ratio': event['play_ratio'],
        'foreground_duration': event['foreground_duration'],
        'background_duration': event['background_duration'],
      });
    });
  }

  // --- Schema Definitions ---

  static const String _statsSchema = '''
    CREATE TABLE IF NOT EXISTS playsession (
      id TEXT PRIMARY KEY,
      start_time REAL,
      end_time REAL,
      platform TEXT
    );
    CREATE TABLE IF NOT EXISTS playevent (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      song_filename TEXT,
      event_type TEXT,
      timestamp REAL,
      duration_played REAL,
      total_length REAL,
      play_ratio REAL,
      foreground_duration REAL,
      background_duration REAL,
      FOREIGN KEY (session_id) REFERENCES playsession (id)
    );
  ''';

  static const String _userDataSchema = '''
    CREATE TABLE IF NOT EXISTS userdata (
      username TEXT PRIMARY KEY,
      password_hash TEXT,
      created_at REAL
    );
    CREATE TABLE IF NOT EXISTS favorite (
      filename TEXT PRIMARY KEY,
      added_at REAL
    );
    CREATE TABLE IF NOT EXISTS suggestless (
      filename TEXT PRIMARY KEY,
      added_at REAL
    );
  ''';
}

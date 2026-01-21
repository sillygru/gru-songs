import 'dart:io';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

/// DatabaseService handles local SQLite storage for offline access.
///
/// SYNC PHILOSOPHY:
/// - Server is the SOURCE OF TRUTH
/// - Client stores local cache for offline access
/// - Favorites/SuggestLess changes use explicit API calls (add/remove)
/// - Stats are additive-only (never delete from server)
/// - DB file uploads are ONLY for stats (which are additive)
class DatabaseService {
  static DatabaseService _instance = DatabaseService._init();
  static DatabaseService get instance => _instance;

  @visibleForTesting
  static set instance(DatabaseService mock) => _instance = mock;

  Database? _statsDatabase;
  Database? _userDataDatabase;
  String? _currentUsername;
  Completer<void>? _initCompleter;

  DatabaseService._init();

  @visibleForTesting
  DatabaseService.forTest();

  Future<void> initForUser(String username) async {
    if (_currentUsername == username && _statsDatabase != null) return;

    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _currentUsername = username;

    try {
      // Open local databases (create schema if needed)
      _statsDatabase =
          await _openDatabase('${username}_stats.db', _statsSchema);
      _userDataDatabase =
          await _openDatabase('${username}_data.db', _userDataSchema);

      _initCompleter!.complete();
    } catch (e) {
      debugPrint('Database initialization failed: $e');
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initCompleter == null) {
      throw Exception(
          'DatabaseService not initialized. Call initForUser first.');
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
        for (final statement in schema.split(';')) {
          if (statement.trim().isNotEmpty) {
            await db.execute(statement);
          }
        }
      },
    );
  }

  // ==========================================================================
  // SYNC METHODS - Proper bidirectional sync with server as source of truth
  // ==========================================================================

  /// Full bidirectional sync (Download latest from server)
  Future<void> sync(String username) async {
    if (await StorageService().getIsLocalMode()) return;
    if (ApiService.baseUrl.isEmpty) {
      debugPrint('Sync skipped: No server URL configured');
      return;
    }
    await downloadStatsFromServer(username);
    await downloadFinalStatsFromServer(username);
  }

  /// Upload local changes to server (Additive merge)
  Future<void> syncBack(String username) async {
    if (await StorageService().getIsLocalMode()) return;
    if (ApiService.baseUrl.isEmpty) return;
    await uploadStatsToServer(username);
  }

  /// Downloads stats DB from server (for offline viewing of play history)
  /// This is a read-only sync - we don't overwrite server stats
  Future<void> downloadStatsFromServer(String username) async {
    if (await StorageService().getIsLocalMode()) return;
    if (ApiService.baseUrl.isEmpty) return;
    final docDir = await getApplicationDocumentsDirectory();
    final path = join(docDir.path, '${username}_stats.db');

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/user/db/stats'),
        headers: {'x-username': username},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Close database before overwriting
        await _statsDatabase?.close();
        _statsDatabase = null;

        final file = File(path);
        await file.writeAsBytes(response.bodyBytes);

        // Reopen
        _statsDatabase =
            await _openDatabase('${username}_stats.db', _statsSchema);
        debugPrint('Downloaded stats DB from server');
      }
    } catch (e) {
      debugPrint('Download stats DB failed (Offline?): $e');
    }
  }

  /// Uploads local stats to server (additive merge on server side)
  /// Server should only ADD new events, never delete existing ones
  Future<void> uploadStatsToServer(String username) async {
    if (await StorageService().getIsLocalMode()) return;
    if (ApiService.baseUrl.isEmpty) return;
    final docDir = await getApplicationDocumentsDirectory();
    final path = join(docDir.path, '${username}_stats.db');
    final file = File(path);

    if (!await file.exists()) return;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/user/db/stats'),
      );
      request.headers['x-username'] = username;
      request.files.add(await http.MultipartFile.fromPath('file', path));

      final response =
          await request.send().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        debugPrint('Uploaded stats DB to server');
      }
    } catch (e) {
      debugPrint('Upload stats DB failed: $e');
    }
  }

  /// Downloads final_stats.json from server (contains shuffle state, etc.)
  Future<void> downloadFinalStatsFromServer(String username) async {
    if (await StorageService().getIsLocalMode()) return;
    if (ApiService.baseUrl.isEmpty) return;
    final docDir = await getApplicationDocumentsDirectory();
    final path = join(docDir.path, '${username}_final_stats.json');

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/user/db/final_stats'),
        headers: {'x-username': username},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final file = File(path);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('Downloaded final_stats from server');
      }
    } catch (e) {
      debugPrint('Download final_stats failed (Offline?): $e');
    }
  }

  // ==========================================================================
  // USER DATA QUERIES (Local cache - synced via API calls, not DB uploads)
  // ==========================================================================

  Future<List<String>> getFavorites() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final results = await _userDataDatabase!.query('favorite');
      return results.map((r) => r['filename'] as String).toList();
    } catch (e) {
      debugPrint('Error getting favorites: $e');
      return [];
    }
  }

  Future<void> addFavorite(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'favorite',
      {
        'filename': filename,
        'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!
        .delete('favorite', where: 'filename = ?', whereArgs: [filename]);
  }

  /// Replaces all local favorites with the given list (used when syncing FROM server)
  Future<void> setFavorites(List<String> favorites) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('favorite');
      for (final filename in favorites) {
        await txn.insert(
            'favorite',
            {
              'filename': filename,
              'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<String>> getSuggestLess() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final results = await _userDataDatabase!.query('suggestless');
      return results.map((r) => r['filename'] as String).toList();
    } catch (e) {
      debugPrint('Error getting suggestless: $e');
      return [];
    }
  }

  Future<void> addSuggestLess(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'suggestless',
      {
        'filename': filename,
        'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeSuggestLess(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!
        .delete('suggestless', where: 'filename = ?', whereArgs: [filename]);
  }

  /// Renames a file in all database tables.
  /// If the target filename already exists, stats are merged.
  Future<void> renameFile(String oldFilename, String newFilename) async {
    await _ensureInitialized();
    if (_statsDatabase == null || _userDataDatabase == null) return;

    // 1. Update User Data DB (Favorites, SuggestLess)
    await _userDataDatabase!.transaction((txn) async {
      // For favorites/suggestless, if target exists, we just delete the old one
      // (effectively "merging" the fact that it is a favorite)

      // Check if new exists in favorite
      final newFav = await txn
          .query('favorite', where: 'filename = ?', whereArgs: [newFilename]);
      if (newFav.isNotEmpty) {
        await txn.delete('favorite',
            where: 'filename = ?', whereArgs: [oldFilename]);
      } else {
        await txn.update('favorite', {'filename': newFilename},
            where: 'filename = ?', whereArgs: [oldFilename]);
      }

      // Check if new exists in suggestless
      final newSL = await txn.query('suggestless',
          where: 'filename = ?', whereArgs: [newFilename]);
      if (newSL.isNotEmpty) {
        await txn.delete('suggestless',
            where: 'filename = ?', whereArgs: [oldFilename]);
      } else {
        await txn.update('suggestless', {'filename': newFilename},
            where: 'filename = ?', whereArgs: [oldFilename]);
      }
    });

    // 2. Update Stats DB (PlayEvents)
    await _statsDatabase!.transaction((txn) async {
      // We always update the filename in playevent.
      // This effectively merges stats because play count queries group by song_filename.
      await txn.update('playevent', {'song_filename': newFilename},
          where: 'song_filename = ?', whereArgs: [oldFilename]);
    });

    debugPrint('Renamed DB entries from $oldFilename to $newFilename');
  }

  /// Replaces all local suggestless with the given list (used when syncing FROM server)
  Future<void> setSuggestLess(List<String> suggestLess) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('suggestless');
      for (final filename in suggestLess) {
        await txn.insert(
            'suggestless',
            {
              'filename': filename,
              'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ==========================================================================
  // PLAYBACK QUERIES
  // ==========================================================================

  Future<Map<String, int>> getPlayCounts() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return {};
    try {
      final results = await _statsDatabase!.rawQuery(
          'SELECT song_filename, COUNT(*) as count FROM playevent WHERE play_ratio > 0.20 GROUP BY song_filename');
      return {
        for (var r in results) r['song_filename'] as String: r['count'] as int
      };
    } catch (e) {
      debugPrint('Error fetching play counts: $e');
      return {};
    }
  }

  Future<Map<String, ({int count, double avgRatio})>> getSkipStats() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return {};
    try {
      // Get count of "immediate skips" and average play ratio for all songs
      final results = await _statsDatabase!.rawQuery(
          'SELECT song_filename, COUNT(CASE WHEN play_ratio < 0.10 THEN 1 END) as skip_count, AVG(play_ratio) as avg_ratio FROM playevent GROUP BY song_filename');
      return {
        for (var r in results)
          r['song_filename'] as String: (
            count: r['skip_count'] as int,
            avgRatio: (r['avg_ratio'] as num).toDouble()
          )
      };
    } catch (e) {
      debugPrint('Error fetching skip stats: $e');
      return {};
    }
  }

  Future<void> insertPlayEvent(Map<String, dynamic> event) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;

    await _statsDatabase!.transaction((txn) async {
      await txn.insert(
          'playsession',
          {
            'id': event['session_id'],
            'start_time': event['timestamp'],
            'end_time': event['timestamp'],
            'platform': event['platform'] ?? 'unknown',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.rawUpdate(
          'UPDATE playsession SET end_time = ? WHERE id = ? AND end_time < ?',
          [event['timestamp'], event['session_id'], event['timestamp']]);

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

  // ==========================================================================
  // SCHEMA DEFINITIONS
  // ==========================================================================

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

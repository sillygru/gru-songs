import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import '../models/playlist.dart';

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
  Timer? _coalesceTimer;

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

      // --- AUTO-MIGRATION: Ensure tables and columns exist ---
      await _ensureTablesAndColumns(_userDataDatabase!);

      // Start background coalescing timer (3 minutes after init, then every 3 minutes)
      _startCoalesceTimer();

      _initCompleter!.complete();
    } catch (e) {
      debugPrint('Database initialization failed: $e');
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _ensureTablesAndColumns(Database db) async {
    // 1. Ensure Tables exist (redundant but safe)
    await db.execute(
        'CREATE TABLE IF NOT EXISTS favorite (filename TEXT PRIMARY KEY, added_at REAL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS suggestless (filename TEXT PRIMARY KEY, added_at REAL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS hidden (filename TEXT PRIMARY KEY, hidden_at REAL)');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS playlist (
          id TEXT PRIMARY KEY,
          name TEXT,
          created_at REAL,
          updated_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS playlist_song (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id TEXT,
          song_filename TEXT,
          added_at REAL,
          FOREIGN KEY (playlist_id) REFERENCES playlist (id)
        )
    ''');

    // 2. Ensure specific columns exist (for future-proofing and existing installs)
    // Example: If we added 'description' to playlist table
    // await _addColumnIfNotExists(db, 'playlist', 'description', 'TEXT');
  }

  // ignore: unused_element
  Future<void> _addColumnIfNotExists(Database db, String tableName,
      String columnName, String columnType) async {
    final List<Map<String, dynamic>> columns =
        await db.rawQuery('PRAGMA table_info($tableName)');
    final bool columnExists =
        columns.any((column) => column['name'] == columnName);

    if (!columnExists) {
      await db
          .execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnType');
      debugPrint('Migration: Added column $columnName to $tableName');
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

  Future<List<String>> getHidden() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final results = await _userDataDatabase!.query('hidden');
      return results.map((r) => r['filename'] as String).toList();
    } catch (e) {
      debugPrint('Error getting hidden: $e');
      return [];
    }
  }

  Future<void> addHidden(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'hidden',
      {
        'filename': filename,
        'hidden_at': DateTime.now().millisecondsSinceEpoch / 1000.0
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeHidden(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!
        .delete('hidden', where: 'filename = ?', whereArgs: [filename]);
  }

  Future<void> setHidden(List<String> hidden) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('hidden');
      for (final filename in hidden) {
        await txn.insert(
            'hidden',
            {
              'filename': filename,
              'hidden_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ==========================================================================
  // PLAYLIST QUERIES
  // ==========================================================================

  Future<List<Playlist>> getPlaylists() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final plMaps = await _userDataDatabase!
          .query('playlist', orderBy: 'updated_at DESC');
      final playlists = <Playlist>[];

      for (final plMap in plMaps) {
        final id = plMap['id'] as String;
        final songs = await _userDataDatabase!.query(
          'playlist_song',
          where: 'playlist_id = ?',
          whereArgs: [id],
          orderBy: 'added_at ASC',
        );

        playlists.add(Playlist(
          id: id,
          name: plMap['name'] as String,
          createdAt: plMap['created_at'] as double,
          updatedAt: plMap['updated_at'] as double,
          songs: songs.map((s) => PlaylistSong.fromJson(s)).toList(),
        ));
      }
      return playlists;
    } catch (e) {
      debugPrint('Error getting playlists: $e');
      return [];
    }
  }

  Future<void> savePlaylist(Playlist playlist) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      // Upsert playlist
      await txn.insert(
        'playlist',
        {
          'id': playlist.id,
          'name': playlist.name,
          'created_at': playlist.createdAt,
          'updated_at': playlist.updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // We don't delete existing songs here to be safe (sync might rely on additive),
      // but if this is a "save whole playlist" call, we probably should replace songs.
      // However, usually we modify incrementally.
      // If we are syncing from server, we might want to replace.
      // Let's assume this method is used for syncing OR creation.

      // Ideally, if we save the whole object, we should match the object state.
      // Delete all songs and re-insert.
      await txn.delete('playlist_song',
          where: 'playlist_id = ?', whereArgs: [playlist.id]);

      for (final song in playlist.songs) {
        await txn.insert('playlist_song', {
          'playlist_id': playlist.id,
          'song_filename': song.songFilename,
          'added_at': song.addedAt,
        });
      }
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('playlist_song',
          where: 'playlist_id = ?', whereArgs: [playlistId]);
      await txn.delete('playlist', where: 'id = ?', whereArgs: [playlistId]);
    });
  }

  Future<void> addSongToPlaylist(String playlistId, String songFilename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      // Check if already exists?
      final existing = await txn.query('playlist_song',
          where: 'playlist_id = ? AND song_filename = ?',
          whereArgs: [playlistId, songFilename]);

      if (existing.isEmpty) {
        await txn.insert('playlist_song', {
          'playlist_id': playlistId,
          'song_filename': songFilename,
          'added_at': now
        });

        // Update playlist timestamp
        await txn.update('playlist', {'updated_at': now},
            where: 'id = ?', whereArgs: [playlistId]);
      }
    });
  }

  Future<void> removeSongFromPlaylist(
      String playlistId, String songFilename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('playlist_song',
          where: 'playlist_id = ? AND song_filename = ?',
          whereArgs: [playlistId, songFilename]);
      // Update playlist timestamp
      await txn.update('playlist',
          {'updated_at': DateTime.now().millisecondsSinceEpoch / 1000.0},
          where: 'id = ?', whereArgs: [playlistId]);
    });
  }

  Future<void> updatePlaylistName(String playlistId, String newName) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.update(
        'playlist',
        {
          'name': newName,
          'updated_at': DateTime.now().millisecondsSinceEpoch / 1000.0
        },
        where: 'id = ?',
        whereArgs: [playlistId]);
  }

  /// Renames a file in all database tables.
  /// If the target filename already exists, stats are merged.
  Future<void> renameFile(String oldFilename, String newFilename) async {
    await _ensureInitialized();
    if (_statsDatabase == null || _userDataDatabase == null) return;

    // 1. Update User Data DB (Favorites, SuggestLess, Hidden)
    await _userDataDatabase!.transaction((txn) async {
      // For favorites/suggestless/hidden, if target exists, we just delete the old one
      // (effectively "merging" the fact that it is a favorite/suggestless/hidden)

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

      // Check if new exists in hidden
      final newHidden = await txn
          .query('hidden', where: 'filename = ?', whereArgs: [newFilename]);
      if (newHidden.isNotEmpty) {
        await txn
            .delete('hidden', where: 'filename = ?', whereArgs: [oldFilename]);
      } else {
        await txn.update('hidden', {'filename': newFilename},
            where: 'filename = ?', whereArgs: [oldFilename]);
      }

      // Update Playlist Songs
      // Get all playlist entries for old filename
      final plSongs = await txn.query('playlist_song',
          where: 'song_filename = ?', whereArgs: [oldFilename]);
      for (final plSong in plSongs) {
        final playlistId = plSong['playlist_id'] as String;
        // Check if new filename already in this playlist
        final existing = await txn.query('playlist_song',
            where: 'playlist_id = ? AND song_filename = ?',
            whereArgs: [playlistId, newFilename]);

        if (existing.isNotEmpty) {
          // Delete old (merge)
          await txn.delete('playlist_song',
              where: 'id = ?', whereArgs: [plSong['id']]);
        } else {
          // Rename
          await txn.update('playlist_song', {'song_filename': newFilename},
              where: 'id = ?', whereArgs: [plSong['id']]);
        }
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

  /// Deletes a file from user data tables only.
  /// Removes the file from favorites, suggestless, hidden, and playlists.
  /// Preserves play events to maintain statistics.
  Future<void> deleteFile(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    // Update User Data DB (Favorites, SuggestLess, Hidden, Playlists)
    await _userDataDatabase!.transaction((txn) async {
      // Remove from favorites
      await txn.delete('favorite', where: 'filename = ?', whereArgs: [filename]);
      
      // Remove from suggestless
      await txn.delete('suggestless', where: 'filename = ?', whereArgs: [filename]);
      
      // Remove from hidden
      await txn.delete('hidden', where: 'filename = ?', whereArgs: [filename]);
      
      // Remove from all playlists
      await txn.delete('playlist_song', where: 'song_filename = ?', whereArgs: [filename]);
    });

    // Note: We DO NOT delete play events to preserve statistics
    debugPrint('Deleted user data entries for file $filename (stats preserved)');
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
          'SELECT song_filename, COUNT(*) as count FROM playevent WHERE play_ratio > 0.25 GROUP BY song_filename');
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

      // Coalesce logic (Fix for fragmented stats)
      final lastEvents = await txn.query(
        'playevent',
        where: 'session_id = ? AND song_filename = ?',
        whereArgs: [event['session_id'], event['song_filename']],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      final totalLength = (event['total_length'] as num).toDouble();

      if (lastEvents.isNotEmpty) {
        final last = lastEvents.first;
        final lastId = last['id'] as int;

        final newDuration = (last['duration_played'] as num) +
            (event['duration_played'] as num);
        final newFg = ((last['foreground_duration'] as num?) ?? 0) +
            ((event['foreground_duration'] as num?) ?? 0);
        final newBg = ((last['background_duration'] as num?) ?? 0) +
            ((event['background_duration'] as num?) ?? 0);
        final newRatio = totalLength > 0 ? newDuration / totalLength : 0.0;

        // Retroactively fix "skips" that are actually full plays (within 10s of end)
        String finalEventType = event['event_type'];
        if (totalLength > 0 && (totalLength - newDuration) <= 10.0) {
          finalEventType = 'complete';
        }

        await txn.update(
            'playevent',
            {
              'duration_played': newDuration,
              'foreground_duration': newFg,
              'background_duration': newBg,
              'event_type': finalEventType,
              'timestamp': event['timestamp'], // Update to latest timestamp
              'play_ratio': newRatio,
            },
            where: 'id = ?',
            whereArgs: [lastId]);
      } else {
        // First insert for this song/session
        String finalEventType = event['event_type'];
        final duration = (event['duration_played'] as num).toDouble();
        if (totalLength > 0 && (totalLength - duration) <= 10.0) {
          finalEventType = 'complete';
        }

        await txn.insert('playevent', {
          'session_id': event['session_id'],
          'song_filename': event['song_filename'],
          'event_type': finalEventType,
          'timestamp': event['timestamp'],
          'duration_played': duration,
          'total_length': totalLength,
          'play_ratio': totalLength > 0 ? duration / totalLength : 0.0,
          'foreground_duration': event['foreground_duration'],
          'background_duration': event['background_duration'],
        });
      }
    });
  }

  Future<Map<String, dynamic>> getFunStats() async {
    await _ensureInitialized();

    if (_statsDatabase == null || _currentUsername == null) {
      return {"stats": []};
    }

    try {
      final events =
          await _statsDatabase!.query('playevent', orderBy: 'timestamp ASC');

      if (events.isEmpty) return {"stats": []};

      // Load metadata from song cache

      final songs = await StorageService().loadSongs(_currentUsername);

      final metadataMap = {for (var s in songs) s.filename: s};

      final favorites = Set<String>.from(await getFavorites());

      double totalTimeSeconds = 0;

      final songCounts = <String, int>{};

      final artistCounts = <String, int>{};

      int totalSkips = 0;

      final playDates = <DateTime>{};

      final hourCounts = <int, int>{};

      final dayCounts = <String, int>{};

      final uniquePlayedSongs = <String>{};

      int favoritesPlayCount = 0;

      int totalMeaningfulPlays = 0;

      for (final event in events) {
        final duration = (event['duration_played'] as num).toDouble();

        final ratio = (event['play_ratio'] as num).toDouble();

        final filename = event['song_filename'] as String;

        final timestamp = (event['timestamp'] as num).toDouble();

        final eventType = event['event_type'] as String;

        totalTimeSeconds += duration;

        final dt =
            DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());

        playDates.add(DateTime(dt.year, dt.month, dt.day));

        hourCounts[dt.hour] = (hourCounts[dt.hour] ?? 0) + 1;

        final dayName = _getDayName(dt.weekday);

        dayCounts[dayName] = (dayCounts[dayName] ?? 0) + 1;

        if (ratio > 0.25) {
          totalMeaningfulPlays++;

          uniquePlayedSongs.add(filename);

          songCounts[filename] = (songCounts[filename] ?? 0) + 1;

          final meta = metadataMap[filename];

          if (meta != null && meta.artist != 'Unknown Artist') {
            artistCounts[meta.artist] = (artistCounts[meta.artist] ?? 0) + 1;
          }

          if (favorites.contains(filename)) {
            favoritesPlayCount++;
          }
        }

        if (ratio <= 0.90 &&
            (eventType == 'skip' ||
                (eventType != 'complete' && ratio < 0.25))) {
          totalSkips++;
        }
      }

      final List<Map<String, dynamic>> stats = [];

      // 1. Total Time

      final hours = totalTimeSeconds ~/ 3600;

      final minutes = (totalTimeSeconds % 3600) ~/ 60;

      stats.add({
        "id": "total_time",
        "label": "Total Listening Time",
        "value": "${hours}h ${minutes}m",
        "subtitle":
            "You've listened for ${(totalTimeSeconds / 86400).toStringAsFixed(1)} days total!"
      });

      // 2. Most Played Artist

      if (artistCounts.isNotEmpty) {
        final topArtist =
            artistCounts.entries.reduce((a, b) => a.value > b.value ? a : b);

        stats.add({
          "id": "top_artist",
          "label": "Most Played Artist",
          "value": topArtist.key,
          "subtitle": "${topArtist.value} plays. You clearly love them."
        });
      }

      // 3. Most Played Song

      if (songCounts.isNotEmpty) {
        final topSong =
            songCounts.entries.reduce((a, b) => a.value > b.value ? a : b);

        final meta = metadataMap[topSong.key];

        stats.add({
          "id": "top_song",
          "label": "Most Played Song",
          "value": meta?.title ?? _getFileNameWithoutExt(topSong.key),
          "subtitle": "Played ${topSong.value} times."
        });
      }

      // 4. Streak

      final sortedDates = playDates.toList()..sort();

      int longestStreak = 0;

      int currentStreak = 0;

      if (sortedDates.isNotEmpty) {
        int tempStreak = 1;

        for (int i = 1; i < sortedDates.length; i++) {
          if (sortedDates[i].difference(sortedDates[i - 1]).inDays == 1) {
            tempStreak++;
          } else {
            longestStreak = max(longestStreak, tempStreak);

            tempStreak = 1;
          }
        }

        longestStreak = max(longestStreak, tempStreak);

        final today = DateTime.now();

        final lastPlay = sortedDates.last;

        final diff = DateTime(today.year, today.month, today.day)
            .difference(lastPlay)
            .inDays;

        if (diff <= 1) {
          currentStreak = 1;

          for (int i = sortedDates.length - 2; i >= 0; i--) {
            if (sortedDates[i + 1].difference(sortedDates[i]).inDays == 1) {
              currentStreak++;
            } else {
              break;
            }
          }
        }
      }

      stats.add({
        "id": "streak",
        "label": "Longest Streak",
        "value": "$longestStreak Days",
        "subtitle": currentStreak > 0
            ? "Current streak: $currentStreak days"
            : "Start a new streak today!"
      });

      // 5. Active Hour

      if (hourCounts.isNotEmpty) {
        final topHour =
            hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b);

        final hourLabel = topHour.key == 0
            ? "12 AM"
            : (topHour.key < 12
                ? "${topHour.key} AM"
                : (topHour.key == 12 ? "12 PM" : "${topHour.key - 12} PM"));

        stats.add({
          "id": "active_hour",
          "label": "Most Active Hour",
          "value": hourLabel,
          "subtitle": "You listen most at this time."
        });
      }

      // 6. Active Day

      if (dayCounts.isNotEmpty) {
        final topDay =
            dayCounts.entries.reduce((a, b) => a.value > b.value ? a : b);

        stats.add({
          "id": "active_day",
          "label": "Most Active Day",
          "value": topDay.key,
          "subtitle": "Your favorite day to jam."
        });
      }

      // 7. Skips

      stats.add({
        "id": "skips",
        "label": "Total Skips",
        "value": totalSkips.toString(),
        "subtitle": "Songs you passed on."
      });

      // 8. Unique Songs

      stats.add({
        "id": "unique_songs",
        "label": "Unique Songs Played",
        "value": uniquePlayedSongs.length.toString(),
        "subtitle": "Distinct tracks you've heard."
      });

      // 9. Total Songs Played

      stats.add({
        "id": "total_songs_played",
        "label": "Total Songs Played",
        "value": totalMeaningfulPlays.toString(),
        "subtitle": "Total times you've jammed out."
      });

      // 10. Explorer Score

      if (songs.isNotEmpty) {
        final exploredPct =
            ((uniquePlayedSongs.length / songs.length) * 100).toInt();

        stats.add({
          "id": "explorer_score",
          "label": "Explorer Score",
          "value": "$exploredPct%",
          "subtitle": "Of your library explored."
        });
      }

      // 10. Consistency Score

      if (totalMeaningfulPlays > 0) {
        final consistency =
            ((favoritesPlayCount / totalMeaningfulPlays) * 100).toInt();

        stats.add({
          "id": "consistency",
          "label": "Consistency Score",
          "value": "$consistency%",
          "subtitle": "Plays that were Favorites."
        });
      }

      return {"stats": stats};
    } catch (e) {
      debugPrint("Error calculating local fun stats: $e");

      return {"stats": []};
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return "Monday";
      case 2:
        return "Tuesday";
      case 3:
        return "Wednesday";
      case 4:
        return "Thursday";
      case 5:
        return "Friday";
      case 6:
        return "Saturday";
      case 7:
        return "Sunday";
      default:
        return "";
    }
  }

  String _getFileNameWithoutExt(String filename) {
    final idx = filename.lastIndexOf('.');
    return idx == -1 ? filename : filename.substring(0, idx);
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
    CREATE TABLE IF NOT EXISTS hidden (
      filename TEXT PRIMARY KEY,
      hidden_at REAL
    );
    CREATE TABLE IF NOT EXISTS playlist (
      id TEXT PRIMARY KEY,
      name TEXT,
      created_at REAL,
      updated_at REAL
    );
    CREATE TABLE IF NOT EXISTS playlist_song (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id TEXT,
      song_filename TEXT,
      added_at REAL,
      FOREIGN KEY (playlist_id) REFERENCES playlist (id)
    );
  ''';

  void _startCoalesceTimer() {
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _lazyCoalesceEvents();
    });
  }

  Future<void> _lazyCoalesceEvents() async {
    if (_statsDatabase == null || _currentUsername == null) return;

    try {
      // Use compute to run in background isolate for performance
      await compute(_coalesceEventsInIsolate, {
        'dbPath': await _getDatabasePath('${_currentUsername}_stats.db'),
      });
    } catch (e) {
      debugPrint('Background coalescing failed: $e');
    }
  }

  static Future<void> _coalesceEventsInIsolate(
      Map<String, String> params) async {
    final dbPath = params['dbPath']!;
    final db = await openDatabase(dbPath);

    try {
      // Get all events ordered by session and timestamp
      final events =
          await db.query('playevent', orderBy: 'session_id, timestamp');

      if (events.isEmpty) return;

      final coalesced = <Map<String, dynamic>>[];
      Map<String, dynamic>? current;

      for (final event in events) {
        if (current == null) {
          current = Map<String, dynamic>.from(event);
          continue;
        }

        // Check if we should merge (same session, same song)
        if (event['session_id'] == current['session_id'] &&
            event['song_filename'] == current['song_filename']) {
          // Merge durations
          current['duration_played'] = (current['duration_played'] as num) +
              (event['duration_played'] as num);
          current['foreground_duration'] =
              ((current['foreground_duration'] as num?) ?? 0) +
                  ((event['foreground_duration'] as num?) ?? 0);
          current['background_duration'] =
              ((current['background_duration'] as num?) ?? 0) +
                  ((event['background_duration'] as num?) ?? 0);

          // Update with latest metadata
          current['event_type'] = event['event_type'];
          current['timestamp'] = event['timestamp'];
        } else {
          // Finalize current event
          _finalizeEvent(current);
          coalesced.add(current);
          current = Map<String, dynamic>.from(event);
        }
      }

      // Add final event
      if (current != null) {
        _finalizeEvent(current);
        coalesced.add(current);
      }

      // Replace in database (only if we actually reduced events)
      if (coalesced.length < events.length) {
        await db.transaction((txn) async {
          await txn.delete('playevent');
          for (final event in coalesced) {
            await txn.insert('playevent', event);
          }
        });
        debugPrint('Coalesced ${events.length} → ${coalesced.length} events');
      }
    } finally {
      await db.close();
    }
  }

  static void _finalizeEvent(Map<String, dynamic> event) {
    final totalLength = (event['total_length'] as num?)?.toDouble() ?? 0.0;
    final duration = (event['duration_played'] as num).toDouble();

    // Recalculate ratio
    event['play_ratio'] = totalLength > 0 ? duration / totalLength : 0.0;

    // Fix skips to complete if within 10 seconds
    if (totalLength > 0 && (totalLength - duration) <= 10.0) {
      event['event_type'] = 'complete';
    }
  }

  Future<String> _getDatabasePath(String dbName) async {
    final docDir = await getApplicationDocumentsDirectory();
    return join(docDir.path, dbName);
  }

  void dispose() {
    _coalesceTimer?.cancel();
    _statsDatabase?.close();
    _userDataDatabase?.close();
  }
}

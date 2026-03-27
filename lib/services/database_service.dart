import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/mood_tag.dart';

import '../models/song.dart';

/// DatabaseService handles local SQLite storage.
class DatabaseService {
  static DatabaseService _instance = DatabaseService._init();
  static DatabaseService get instance => _instance;

  @visibleForTesting
  static set instance(DatabaseService mock) => _instance = mock;

  Database? _statsDatabase;
  Database? _userDataDatabase;
  Completer<void>? _initCompleter;

  DatabaseService._init();

  @visibleForTesting
  DatabaseService.forTest();

  Future<bool> init() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      return false;
    }

    _initCompleter = Completer<void>();
    bool migrated = false;

    try {
      // --- MIGRATION LOGIC ---
      migrated = await _performMigrationIfNeeded();

      // Open local databases (create schema if needed)
      _statsDatabase = await _openDatabase('wispie_stats.db', _statsSchema);
      _userDataDatabase =
          await _openDatabase('wispie_data.db', _userDataSchema);

      // --- AUTO-MIGRATION: Ensure tables and columns exist ---
      await _ensureStatsTables(_statsDatabase!);
      await _ensureTablesAndColumns(_userDataDatabase!);

      _initCompleter!.complete();
      return migrated;
    } catch (e) {
      debugPrint('Database initialization failed: $e');
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<bool> _performMigrationIfNeeded() async {
    final docDir = await getApplicationDocumentsDirectory();
    final newDataDb = File(join(docDir.path, 'wispie_data.db'));

    // If new DB already exists, migration is done.
    if (await newDataDb.exists()) return false;

    bool migrated = false;
    // Check for old user to migrate
    final prefs = await SharedPreferences.getInstance();
    // Try 'local_username' first (from StorageService), then 'username' (legacy Auth)
    final username =
        prefs.getString('local_username') ?? prefs.getString('username');

    if (username != null) {
      debugPrint('Migrating data for user: $username');
      final oldDataDb = File(join(docDir.path, '${username}_data.db'));
      final oldStatsDb = File(join(docDir.path, '${username}_stats.db'));

      if (await oldDataDb.exists()) {
        await oldDataDb.rename(newDataDb.path);
        debugPrint('Migrated data DB');
        migrated = true;
      }

      if (await oldStatsDb.exists()) {
        await oldStatsDb.rename(join(docDir.path, 'wispie_stats.db'));
        debugPrint('Migrated stats DB');
        migrated = true;
      }

      // Rename JSON caches
      final oldSongsJson =
          File(join(docDir.path, 'cached_songs_$username.json'));
      if (await oldSongsJson.exists()) {
        await oldSongsJson.rename(join(docDir.path, 'cached_songs.json'));
        migrated = true;
      }

      final oldUserDataJson =
          File(join(docDir.path, 'user_data_$username.json'));
      if (await oldUserDataJson.exists()) {
        await oldUserDataJson.rename(join(docDir.path, 'user_data.json'));
        migrated = true;
      }

      final oldShuffleJson =
          File(join(docDir.path, 'shuffle_state_$username.json'));
      if (await oldShuffleJson.exists()) {
        await oldShuffleJson.rename(join(docDir.path, 'shuffle_state.json'));
        migrated = true;
      }

      final oldPlaybackJson =
          File(join(docDir.path, 'playback_state_$username.json'));
      if (await oldPlaybackJson.exists()) {
        await oldPlaybackJson.rename(join(docDir.path, 'playback_state.json'));
        migrated = true;
      }
    }

    // Cleanup: Delete ALL old user DBs and JSONs (for all users, including the one we just migrated from if copy failed/renamed, or others)

    // Actually, since we renamed, the old files for the current user are gone (if rename worked).

    // Now we just delete anything that looks like a user DB but isn't wispie_*.

    try {
      if (await docDir.exists()) {
        final entities = docDir.listSync();

        for (final entity in entities) {
          if (entity is File) {
            final name = basename(entity.path);

            // Delete old DBs

            if ((name.endsWith('_data.db') || name.endsWith('_stats.db')) &&
                !name.startsWith('wispie_')) {
              debugPrint('Deleting old DB: $name');

              try {
                await entity.delete();
              } catch (_) {}
            }

            // Delete old JSONs

            if ((name.startsWith('cached_songs_') ||
                    name.startsWith('user_data_') ||
                    name.startsWith('shuffle_state_') ||
                    name.startsWith('playback_state_')) &&
                name.endsWith('.json')) {
              debugPrint('Deleting old JSON: $name');

              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old files: $e');
    }
    return migrated;
  }

  Future<void> _ensureStatsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playsession (
        id TEXT PRIMARY KEY,
        start_time REAL,
        end_time REAL,
        platform TEXT
      )
    ''');
    await db.execute('''
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
      )
    ''');
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
        CREATE TABLE IF NOT EXISTS song (
          filename TEXT PRIMARY KEY,
          title TEXT,
          artist TEXT,
          album TEXT,
          url TEXT,
          cover_url TEXT,
          has_lyrics INTEGER,
          play_count INTEGER,
          duration_ms INTEGER,
          mtime REAL,
          created_epoch_sec REAL,
          song_date_epoch_sec REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS playlist (
          id TEXT PRIMARY KEY,
          name TEXT,
          description TEXT,
          is_recommendation INTEGER DEFAULT 0,
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
    await db.execute('''
        CREATE TABLE IF NOT EXISTS merged_song_group (
          id TEXT PRIMARY KEY,
          priority_filename TEXT,
          created_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS merged_song (
          filename TEXT PRIMARY KEY,
          group_id TEXT,
          added_at REAL,
          FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS recommendation_preference (
          id TEXT PRIMARY KEY,
          custom_title TEXT,
          is_pinned INTEGER DEFAULT 0,
          updated_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS recommendation_removal (
          id TEXT PRIMARY KEY,
          removed_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS mood_tag (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          normalized_name TEXT UNIQUE NOT NULL,
          is_preset INTEGER DEFAULT 0,
          created_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS song_mood (
          song_filename TEXT NOT NULL,
          mood_id TEXT NOT NULL,
          added_at REAL,
          source TEXT DEFAULT 'manual',
          PRIMARY KEY (song_filename, mood_id),
          FOREIGN KEY (mood_id) REFERENCES mood_tag (id) ON DELETE CASCADE
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS queue_snapshot (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at REAL NOT NULL,
          source TEXT NOT NULL,
          song_count INTEGER NOT NULL DEFAULT 0
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS queue_snapshot_song (
          snapshot_id TEXT NOT NULL,
          song_filename TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (snapshot_id, position),
          FOREIGN KEY (snapshot_id) REFERENCES queue_snapshot (id) ON DELETE CASCADE
        )
    ''');

    // 2. Ensure specific columns exist (for future-proofing and existing installs)
    await _addColumnIfNotExists(
        db, 'merged_song_group', 'priority_filename', 'TEXT');
    await _addColumnIfNotExists(db, 'playlist', 'description', 'TEXT');
    await _addColumnIfNotExists(
        db, 'playlist', 'is_recommendation', 'INTEGER DEFAULT 0');
    await _addColumnIfNotExists(db, 'song', 'created_epoch_sec', 'REAL');
    await _addColumnIfNotExists(db, 'song', 'song_date_epoch_sec', 'REAL');

    // 3. Create indexes for the song table
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_song_artist ON song(artist)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_song_album ON song(album)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_song_mtime ON song(mtime)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_created_epoch_sec ON song(created_epoch_sec)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_date_epoch_sec ON song(song_date_epoch_sec)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_mood_song_filename ON song_mood(song_filename)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_mood_mood_id ON song_mood(mood_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_tag_normalized_name ON mood_tag(normalized_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_created_at ON queue_snapshot(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_song_snapshot_id ON queue_snapshot_song(snapshot_id)');
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
      throw Exception('DatabaseService not initialized. Call init() first.');
    }
    return _initCompleter!.future;
  }

  /// Ensures the database is initialized
  /// Throws if not initialized
  Future<void> ensureInitialized() async {
    await _ensureInitialized();
  }

  /// Gets the stats database for direct raw queries
  /// Returns null if not initialized
  Database? getStatsDatabase() {
    return _statsDatabase;
  }

  /// Gets the user data database for direct raw queries
  /// Returns null if not initialized
  Database? getUserDataDatabase() {
    return _userDataDatabase;
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
  // STATS METHODS
  // ==========================================================================

  Future<void> addPlayEvent(Map<String, dynamic> stats) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;

    await _statsDatabase!.insert('playevent', stats);
  }

  Future<List<Map<String, dynamic>>> getAllPlayEvents() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return [];
    return await _statsDatabase!.query('playevent');
  }

  Future<void> deletePlayEvent(String sessionId) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;
    await _statsDatabase!
        .delete('playevent', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  // ==========================================================================
  // SESSION HISTORY QUERIES
  // ==========================================================================

  /// Gets all play sessions ordered by start time (newest first)
  /// Filters out sessions shorter than minDurationSeconds
  Future<List<Map<String, dynamic>>> getPlaySessions(
      {int minDurationSeconds = 30}) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return [];

    try {
      final results = await _statsDatabase!.rawQuery('''
        SELECT 
          ps.id,
          ps.start_time,
          ps.end_time,
          ps.platform,
          COUNT(pe.id) as song_count,
          SUM(pe.duration_played) as total_duration
        FROM playsession ps
        LEFT JOIN playevent pe ON ps.id = pe.session_id
        GROUP BY ps.id
        HAVING (ps.end_time - ps.start_time) >= ? OR song_count > 0
        ORDER BY ps.start_time DESC
      ''', [minDurationSeconds]);

      return results;
    } catch (e) {
      debugPrint('Error getting play sessions: $e');
      return [];
    }
  }

  /// Gets all play events for a specific session, ordered by timestamp (oldest first)
  Future<List<Map<String, dynamic>>> getPlayEventsForSession(
      String sessionId) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return [];

    try {
      final results = await _statsDatabase!.query(
        'playevent',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
      );
      return results;
    } catch (e) {
      debugPrint('Error getting play events for session: $e');
      return [];
    }
  }

  /// Clears all play events and sessions
  Future<void> clearStats() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;

    await _statsDatabase!.transaction((txn) async {
      await txn.delete('playevent');
      await txn.delete('playsession');
    });
    debugPrint('Cleared all play stats and sessions');
  }

  // ==========================================================================
  // QUEUE SNAPSHOT QUERIES
  // ==========================================================================

  Future<void> saveQueueSnapshot(String id, String name, double createdAt,
      String source, List<String> songFilenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.insert(
        'queue_snapshot',
        {
          'id': id,
          'name': name,
          'created_at': createdAt,
          'source': source,
          'song_count': songFilenames.length,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete('queue_snapshot_song',
          where: 'snapshot_id = ?', whereArgs: [id]);

      final batch = txn.batch();
      for (int i = 0; i < songFilenames.length; i++) {
        batch.insert('queue_snapshot_song', {
          'snapshot_id': id,
          'song_filename': songFilenames[i],
          'position': i,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateQueueSnapshotSongs(
      String id, List<String> songFilenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('queue_snapshot_song',
          where: 'snapshot_id = ?', whereArgs: [id]);

      final batch = txn.batch();
      for (int i = 0; i < songFilenames.length; i++) {
        batch.insert('queue_snapshot_song', {
          'snapshot_id': id,
          'song_filename': songFilenames[i],
          'position': i,
        });
      }
      await batch.commit(noResult: true);

      await txn.update(
        'queue_snapshot',
        {'song_count': songFilenames.length},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getQueueSnapshots() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      return await _userDataDatabase!.query(
        'queue_snapshot',
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      debugPrint('Error getting queue snapshots: $e');
      return [];
    }
  }

  Future<List<String>> getQueueSnapshotSongs(String snapshotId) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      final results = await _userDataDatabase!.query(
        'queue_snapshot_song',
        where: 'snapshot_id = ?',
        whereArgs: [snapshotId],
        orderBy: 'position ASC',
      );
      return results.map((r) => r['song_filename'] as String).toList();
    } catch (e) {
      debugPrint('Error getting queue snapshot songs: $e');
      return [];
    }
  }

  Future<void> deleteQueueSnapshot(String id) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('queue_snapshot_song',
          where: 'snapshot_id = ?', whereArgs: [id]);
      await txn.delete('queue_snapshot', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> clearQueueHistory() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('queue_snapshot_song');
      await txn.delete('queue_snapshot');
    });
  }

  Future<List<Map<String, dynamic>>> exportQueueHistory() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    final snapshots = await getQueueSnapshots();
    final result = <Map<String, dynamic>>[];

    for (final snapshot in snapshots) {
      final snapshotId = snapshot['id'] as String;
      final songs = await getQueueSnapshotSongs(snapshotId);
      result.add({
        'id': snapshotId,
        'name': snapshot['name'],
        'created_at': snapshot['created_at'],
        'source': snapshot['source'],
        'songs': songs,
      });
    }

    return result;
  }

  Future<void> importQueueHistory(List<Map<String, dynamic>> data) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('queue_snapshot_song');
      await txn.delete('queue_snapshot');

      for (final snapshot in data) {
        final snapshotId = snapshot['id'] as String;
        final name = snapshot['name'] as String;
        final createdAt = (snapshot['created_at'] as num).toDouble();
        final source = snapshot['source'] as String? ?? 'imported';
        final songs = (snapshot['songs'] as List?)?.cast<String>() ?? [];

        await txn.insert('queue_snapshot', {
          'id': snapshotId,
          'name': name,
          'created_at': createdAt,
          'source': source,
          'song_count': songs.length,
        });

        for (int i = 0; i < songs.length; i++) {
          await txn.insert('queue_snapshot_song', {
            'snapshot_id': snapshotId,
            'song_filename': songs[i],
            'position': i,
          });
        }
      }
    });
  }

  // ==========================================================================
  // SONG QUERIES
  // ==========================================================================

  Future<void> insertSongsBatch(List<Song> songs) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      final batch = txn.batch();
      for (final song in songs) {
        batch.insert(
          'song',
          {
            'filename': song.filename,
            'title': song.title,
            'artist': song.artist,
            'album': song.album,
            'url': song.url,
            'cover_url': song.coverUrl,
            'has_lyrics': song.hasLyrics ? 1 : 0,
            'play_count': song.playCount,
            'duration_ms': song.duration?.inMilliseconds,
            'mtime': song.mtime,
            'created_epoch_sec': song.createdEpochSec,
            'song_date_epoch_sec': song.songDateEpochSec,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Song>> getAllSongs() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.query('song');
    return results.map((r) => _mapToSong(r)).toList();
  }

  Future<List<Song>> getSongs(
      {int? limit,
      int? offset,
      String? orderBy,
      String? where,
      List<Object?>? whereArgs}) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.query(
      'song',
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      where: where,
      whereArgs: whereArgs,
    );
    return results.map((r) => _mapToSong(r)).toList();
  }

  Future<int> getSongCount() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return 0;
    final result =
        await _userDataDatabase!.rawQuery('SELECT COUNT(*) as count FROM song');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearSongs() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.delete('song');
  }

  Future<List<String>> getArtists() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.rawQuery(
        'SELECT DISTINCT artist FROM song ORDER BY artist COLLATE NOCASE');
    return results.map((r) => r['artist'] as String).toList();
  }

  Future<List<String>> getAlbums() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.rawQuery(
        'SELECT DISTINCT album FROM song ORDER BY album COLLATE NOCASE');
    return results.map((r) => r['album'] as String).toList();
  }

  Song _mapToSong(Map<String, dynamic> r) {
    return Song(
      title: r['title'] as String,
      artist: r['artist'] as String,
      album: r['album'] as String,
      filename: r['filename'] as String,
      url: r['url'] as String,
      coverUrl: r['cover_url'] as String?,
      hasLyrics: (r['has_lyrics'] as int) == 1,
      playCount: r['play_count'] as int,
      duration: r['duration_ms'] != null
          ? Duration(milliseconds: r['duration_ms'] as int)
          : null,
      mtime: (r['mtime'] as num?)?.toDouble(),
      createdEpochSec: (r['created_epoch_sec'] as num?)?.toDouble(),
      songDateEpochSec: (r['song_date_epoch_sec'] as num?)?.toDouble(),
    );
  }

  // ==========================================================================
  // USER DATA QUERIES
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

  /// Replaces all local favorites with the given list
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
          description: plMap['description'] as String?,
          isRecommendation: (plMap['is_recommendation'] as int? ?? 0) == 1,
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
          'description': playlist.description,
          'is_recommendation': playlist.isRecommendation ? 1 : 0,
          'created_at': playlist.createdAt,
          'updated_at': playlist.updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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

  // Deep validation of all recommendation playlist DB entries.
  // Re-reads every row and every song entry using the same casts as getPlaylists().
  // Returns false if even one field fails to parse correctly, triggering a regeneration.
  Future<bool> validateRecommendationPlaylists() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return false;
    try {
      final plMaps = await _userDataDatabase!.query(
        'playlist',
        where: 'is_recommendation = 1',
      );

      if (plMaps.isEmpty) return false;

      for (final plMap in plMaps) {
        final id = plMap['id'];
        final name = plMap['name'];
        final isRec = plMap['is_recommendation'];
        final createdAt = plMap['created_at'];
        final updatedAt = plMap['updated_at'];

        if (id == null || id is! String || id.isEmpty) return false;
        if (name == null || name is! String) return false;
        if (isRec == null || isRec is! int) return false;
        if (createdAt == null || createdAt is! num) return false;
        if (updatedAt == null || updatedAt is! num) return false;

        final songMaps = await _userDataDatabase!.query(
          'playlist_song',
          where: 'playlist_id = ?',
          whereArgs: [id],
        );

        for (final s in songMaps) {
          final filename = s['song_filename'];
          final addedAt = s['added_at'];

          if (filename == null || filename is! String || filename.isEmpty) {
            return false;
          }
          if (addedAt == null || addedAt is! num) return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Recommendation DB validation error: $e');
      return false;
    }
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

  Future<void> bulkAddSongsToPlaylist(
      String playlistId, List<String> filenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      for (final filename in filenames) {
        final existing = await txn.query('playlist_song',
            where: 'playlist_id = ? AND song_filename = ?',
            whereArgs: [playlistId, filename]);

        if (existing.isEmpty) {
          await txn.insert('playlist_song', {
            'playlist_id': playlistId,
            'song_filename': filename,
            'added_at': now
          });
        }
      }

      // Update playlist timestamp once
      await txn.update('playlist', {'updated_at': now},
          where: 'id = ?', whereArgs: [playlistId]);
    });
  }

  Future<void> bulkRemoveSongsFromPlaylist(
      String playlistId, List<String> filenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      for (final filename in filenames) {
        await txn.delete('playlist_song',
            where: 'playlist_id = ? AND song_filename = ?',
            whereArgs: [playlistId, filename]);
      }

      // Update playlist timestamp
      await txn.update('playlist', {'updated_at': now},
          where: 'id = ?', whereArgs: [playlistId]);
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

    // 1. Update User Data DB (Songs, Favorites, SuggestLess, Hidden, Merged Songs)
    await _userDataDatabase!.transaction((txn) async {
      // Update Song table
      await txn.update('song', {'filename': newFilename},
          where: 'filename = ?', whereArgs: [oldFilename]);

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

      // Update Merged Songs - if old filename is in a merge group, update it
      await txn.update('merged_song', {'filename': newFilename},
          where: 'filename = ?', whereArgs: [oldFilename]);
      await txn.update('song_mood', {'song_filename': newFilename},
          where: 'song_filename = ?', whereArgs: [oldFilename]);

      // Update merged_song_group priority_filename if it matches old filename
      await txn.update('merged_song_group', {'priority_filename': newFilename},
          where: 'priority_filename = ?', whereArgs: [oldFilename]);

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
  /// Removes the file from songs, favorites, suggestless, hidden, merged songs, and playlists.
  /// Preserves play events to maintain statistics.
  Future<void> deleteFile(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    // Update User Data DB (Songs, Favorites, SuggestLess, Hidden, Merged Songs, Playlists)
    await _userDataDatabase!.transaction((txn) async {
      // Remove from songs
      await txn.delete('song', where: 'filename = ?', whereArgs: [filename]);

      // Remove from favorites
      await txn
          .delete('favorite', where: 'filename = ?', whereArgs: [filename]);

      // Remove from suggestless
      await txn
          .delete('suggestless', where: 'filename = ?', whereArgs: [filename]);

      // Remove from hidden
      await txn.delete('hidden', where: 'filename = ?', whereArgs: [filename]);

      // Remove from merged songs (this will auto-delete the group if empty due to ON DELETE CASCADE)
      await txn
          .delete('merged_song', where: 'filename = ?', whereArgs: [filename]);

      // Clean up empty merge groups
      await txn.delete('merged_song_group',
          where:
              'id NOT IN (SELECT DISTINCT group_id FROM merged_song WHERE group_id IS NOT NULL)');

      // Remove from all playlists
      await txn.delete('playlist_song',
          where: 'song_filename = ?', whereArgs: [filename]);
      await txn.delete('song_mood',
          where: 'song_filename = ?', whereArgs: [filename]);
    });

    // Note: We DO NOT delete play events to preserve statistics
    debugPrint(
        'Deleted user data entries for file $filename (stats preserved)');
  }

  /// Replaces all local suggestless with the given list
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
  // MOODS QUERIES
  // ==========================================================================

  Future<List<MoodTag>> getMoodTags() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      final rows = await _userDataDatabase!.query(
        'mood_tag',
        orderBy: 'is_preset DESC, name COLLATE NOCASE ASC',
      );
      return rows.map((row) => MoodTag.fromJson(row)).toList();
    } catch (e) {
      debugPrint('Error getting mood tags: $e');
      return [];
    }
  }

  Future<void> saveMoodTag(MoodTag tag) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.insert(
      'mood_tag',
      tag.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> renameMoodTag(String moodId, String newName) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.update(
      'mood_tag',
      {
        'name': newName.trim(),
        'normalized_name': newName.trim().toLowerCase(),
      },
      where: 'id = ?',
      whereArgs: [moodId],
    );
  }

  Future<void> deleteMoodTag(String moodId) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('song_mood', where: 'mood_id = ?', whereArgs: [moodId]);
      await txn.delete('mood_tag', where: 'id = ?', whereArgs: [moodId]);
    });
  }

  Future<Map<String, List<String>>> getSongMoodMap() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return {};

    try {
      final rows = await _userDataDatabase!.query(
        'song_mood',
        orderBy: 'added_at ASC',
      );

      final map = <String, List<String>>{};
      for (final row in rows) {
        final filename = row['song_filename'] as String;
        final moodId = row['mood_id'] as String;
        map.putIfAbsent(filename, () => <String>[]).add(moodId);
      }
      return map;
    } catch (e) {
      debugPrint('Error getting song moods: $e');
      return {};
    }
  }

  Future<void> setSongMoods(String songFilename, List<String> moodIds) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    await _userDataDatabase!.transaction((txn) async {
      await txn.delete('song_mood',
          where: 'song_filename = ?', whereArgs: [songFilename]);
      for (final moodId in moodIds.toSet()) {
        await txn.insert(
            'song_mood',
            {
              'song_filename': songFilename,
              'mood_id': moodId,
              'added_at': now,
              'source': 'manual',
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ==========================================================================
  // MERGED SONGS QUERIES
  // ==========================================================================

  /// Gets all merged song groups with their filenames and priority info
  /// Returns a map of groupId -> {filenames: [...], priorityFilename: ...}
  Future<Map<String, ({List<String> filenames, String? priorityFilename})>>
      getMergedSongGroups() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return {};

    try {
      // Get groups with priority
      final groupResults = await _userDataDatabase!.query('merged_song_group');
      final groupPriorities = <String, String?>{};
      for (final row in groupResults) {
        groupPriorities[row['id'] as String] =
            row['priority_filename'] as String?;
      }

      // Get all songs
      final results = await _userDataDatabase!.rawQuery('''
        SELECT g.id as group_id, m.filename
        FROM merged_song_group g
        JOIN merged_song m ON g.id = m.group_id
        ORDER BY g.id, m.added_at
      ''');

      final groups = <String, List<String>>{};
      for (final row in results) {
        final groupId = row['group_id'] as String;
        final filename = row['filename'] as String;
        groups.putIfAbsent(groupId, () => []).add(filename);
      }

      // Combine into result format
      final result =
          <String, ({List<String> filenames, String? priorityFilename})>{};
      for (final entry in groups.entries) {
        result[entry.key] = (
          filenames: entry.value,
          priorityFilename: groupPriorities[entry.key],
        );
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching merged song groups: $e');
      return {};
    }
  }

  /// Gets the priority filename for a merge group
  Future<String?> getMergedGroupPriority(String groupId) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return null;

    try {
      final results = await _userDataDatabase!.query(
        'merged_song_group',
        where: 'id = ?',
        whereArgs: [groupId],
        limit: 1,
      );
      if (results.isNotEmpty) {
        return results.first['priority_filename'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching merged group priority: $e');
      return null;
    }
  }

  /// Sets the priority filename for a merge group
  Future<void> setMergedGroupPriority(
      String groupId, String? priorityFilename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    try {
      await _userDataDatabase!.update(
        'merged_song_group',
        {'priority_filename': priorityFilename},
        where: 'id = ?',
        whereArgs: [groupId],
      );
      debugPrint('Set priority for group $groupId to $priorityFilename');
    } catch (e) {
      debugPrint('Error setting merged group priority: $e');
    }
  }

  /// Gets the group ID for a specific filename if it's part of a merge group
  Future<String?> getMergedGroupId(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return null;

    try {
      final results = await _userDataDatabase!.query(
        'merged_song',
        where: 'filename = ?',
        whereArgs: [filename],
        limit: 1,
      );
      if (results.isNotEmpty) {
        return results.first['group_id'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching merged group id: $e');
      return null;
    }
  }

  /// Gets all filenames in the same merge group as the given filename
  Future<List<String>> getMergedSiblings(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      final groupId = await getMergedGroupId(filename);
      if (groupId == null) return [];

      final results = await _userDataDatabase!.query(
        'merged_song',
        where: 'group_id = ? AND filename != ?',
        whereArgs: [groupId, filename],
      );
      return results.map((r) => r['filename'] as String).toList();
    } catch (e) {
      debugPrint('Error fetching merged siblings: $e');
      return [];
    }
  }

  /// Creates a new merge group with the given filenames
  /// [priorityFilename] is the song that should be prioritized during shuffle
  Future<String> createMergedGroup(List<String> filenames,
      {String? priorityFilename}) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) {
      throw Exception('Database not initialized');
    }

    if (filenames.length < 2) {
      throw Exception('Need at least 2 songs to merge');
    }

    // Validate priority filename is in the list
    final effectivePriority =
        priorityFilename != null && filenames.contains(priorityFilename)
            ? priorityFilename
            : null;

    final groupId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      // Create the group with priority
      await txn.insert('merged_song_group', {
        'id': groupId,
        'priority_filename': effectivePriority,
        'created_at': now,
      });

      // Add all songs to the group
      for (final filename in filenames) {
        await txn.insert(
            'merged_song',
            {
              'filename': filename,
              'group_id': groupId,
              'added_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    debugPrint(
        'Created merged group $groupId with ${filenames.length} songs, priority: $effectivePriority');
    return groupId;
  }

  /// Adds songs to an existing merge group
  Future<void> addSongsToMergedGroup(
      String groupId, List<String> filenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      for (final filename in filenames) {
        await txn.insert(
            'merged_song',
            {
              'filename': filename,
              'group_id': groupId,
              'added_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    debugPrint('Added ${filenames.length} songs to merged group $groupId');
  }

  /// Removes a song from its merge group
  Future<void> removeSongFromMergedGroup(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      await txn
          .delete('merged_song', where: 'filename = ?', whereArgs: [filename]);

      // Clean up empty groups
      await txn.delete('merged_song_group',
          where:
              'id NOT IN (SELECT DISTINCT group_id FROM merged_song WHERE group_id IS NOT NULL)');
    });

    debugPrint('Removed $filename from merged group');
  }

  /// Deletes an entire merge group
  Future<void> deleteMergedGroup(String groupId) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      // Delete all songs in the group (cascade will handle the group)
      await txn
          .delete('merged_song', where: 'group_id = ?', whereArgs: [groupId]);
      // Delete the group itself
      await txn
          .delete('merged_song_group', where: 'id = ?', whereArgs: [groupId]);
    });

    debugPrint('Deleted merged group $groupId');
  }

  // ==========================================================================
  // RECOMMENDATION PREFERENCE QUERIES
  // ==========================================================================

  Future<Map<String, ({String? customTitle, bool isPinned})>>
      getRecommendationPreferences() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return {};

    try {
      final results =
          await _userDataDatabase!.query('recommendation_preference');
      final prefs = <String, ({String? customTitle, bool isPinned})>{};
      for (final row in results) {
        prefs[row['id'] as String] = (
          customTitle: row['custom_title'] as String?,
          isPinned: (row['is_pinned'] as int) == 1,
        );
      }
      return prefs;
    } catch (e) {
      debugPrint('Error getting recommendation preferences: $e');
      return {};
    }
  }

  Future<void> saveRecommendationPreference(String id,
      {String? customTitle, bool? isPinned}) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final Map<String, dynamic> values = {'updated_at': now};
    if (customTitle != null) values['custom_title'] = customTitle;
    if (isPinned != null) values['is_pinned'] = isPinned ? 1 : 0;

    await _userDataDatabase!.transaction((txn) async {
      final existing = await txn
          .query('recommendation_preference', where: 'id = ?', whereArgs: [id]);
      if (existing.isEmpty) {
        await txn.insert('recommendation_preference', {'id': id, ...values});
      } else {
        await txn.update('recommendation_preference', values,
            where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<List<String>> getRemovedRecommendations() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      final results = await _userDataDatabase!.query('recommendation_removal');
      return results.map((r) => r['id'] as String).toList();
    } catch (e) {
      debugPrint('Error getting removed recommendations: $e');
      return [];
    }
  }

  Future<void> addRecommendationRemoval(String id) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.insert(
      'recommendation_removal',
      {
        'id': id,
        'removed_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeRecommendationRemoval(String id) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!
        .delete('recommendation_removal', where: 'id = ?', whereArgs: [id]);
  }

  /// Replaces all merged groups with the given data (used for import/restore)
  /// Each entry should be: groupId -> (filenames: [...], priorityFilename: ...)
  Future<void> setMergedGroups(
      Map<String, ({List<String> filenames, String? priorityFilename})>
          groups) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await _userDataDatabase!.transaction((txn) async {
      // Clear existing
      await txn.delete('merged_song');
      await txn.delete('merged_song_group');

      // Insert new groups
      for (final entry in groups.entries) {
        final groupId = entry.key;
        final filenames = entry.value.filenames;
        final priorityFilename = entry.value.priorityFilename;

        if (filenames.length < 2) continue;

        await txn.insert('merged_song_group', {
          'id': groupId,
          'priority_filename': priorityFilename,
          'created_at': now,
        });

        for (final filename in filenames) {
          await txn.insert('merged_song', {
            'filename': filename,
            'group_id': groupId,
            'added_at': now,
          });
        }
      }
    });

    debugPrint('Set ${groups.length} merged groups');
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
      await _insertPlayEventTxn(txn, event);
    });
  }

  Future<void> insertPlayEventsBatch(List<Map<String, dynamic>> events) async {
    await _ensureInitialized();
    if (_statsDatabase == null || events.isEmpty) return;

    await _statsDatabase!.transaction((txn) async {
      for (final event in events) {
        await _insertPlayEventTxn(txn, event);
      }
    });
  }

  Future<void> _insertPlayEventTxn(
      Transaction txn, Map<String, dynamic> event) async {
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

      final newDuration =
          (last['duration_played'] as num) + (event['duration_played'] as num);
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
  }

  Future<
      List<
          ({
            String filename,
            double timestamp,
            double playRatio,
            String eventType
          })>> getPlayHistory({
    int limit = 200,
  }) async {
    await _ensureInitialized();

    if (_statsDatabase == null) {
      return [];
    }

    try {
      // Get all recent play events with their actual play ratios
      // This allows weighting logic to differentiate between barely-listened and fully-listened songs
      final events = await _statsDatabase!.query(
        'playevent',
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return events.map((e) {
        return (
          filename: e['song_filename'] as String,
          timestamp: (e['timestamp'] as num).toDouble(),
          playRatio: (e['play_ratio'] as num).toDouble(),
          eventType: e['event_type'] as String,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting play history: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getFunStats() async {
    await _ensureInitialized();

    if (_statsDatabase == null) {
      return {"stats": []};
    }

    try {
      final events =
          await _statsDatabase!.query('playevent', orderBy: 'timestamp ASC');

      if (events.isEmpty) return {"stats": []};

      // Load metadata from song cache

      final songs = await getAllSongs();

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
      description TEXT,
      is_recommendation INTEGER DEFAULT 0,
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
    CREATE TABLE IF NOT EXISTS merged_song_group (
      id TEXT PRIMARY KEY,
      priority_filename TEXT,
      created_at REAL
    );
    CREATE TABLE IF NOT EXISTS merged_song (
      filename TEXT PRIMARY KEY,
      group_id TEXT,
      added_at REAL,
      FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS mood_tag (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT UNIQUE NOT NULL,
      is_preset INTEGER DEFAULT 0,
      created_at REAL
    );
    CREATE TABLE IF NOT EXISTS song_mood (
      song_filename TEXT NOT NULL,
      mood_id TEXT NOT NULL,
      added_at REAL,
      source TEXT DEFAULT 'manual',
      PRIMARY KEY (song_filename, mood_id),
      FOREIGN KEY (mood_id) REFERENCES mood_tag (id) ON DELETE CASCADE
    );
  ''';

  /// Canonical CREATE TABLE statements for wispie_data.db, keyed by table name.
  /// This is the single source of truth used by DatabaseOptimizerService.
  static const Map<String, String> userDataTableSql = {
    'userdata': '''CREATE TABLE IF NOT EXISTS userdata (
      username TEXT PRIMARY KEY,
      password_hash TEXT,
      created_at REAL
    )''',
    'favorite': '''CREATE TABLE IF NOT EXISTS favorite (
      filename TEXT PRIMARY KEY,
      added_at REAL
    )''',
    'suggestless': '''CREATE TABLE IF NOT EXISTS suggestless (
      filename TEXT PRIMARY KEY,
      added_at REAL
    )''',
    'hidden': '''CREATE TABLE IF NOT EXISTS hidden (
      filename TEXT PRIMARY KEY,
      hidden_at REAL
    )''',
    'song': '''CREATE TABLE IF NOT EXISTS song (
      filename TEXT PRIMARY KEY,
      title TEXT,
      artist TEXT,
      album TEXT,
      url TEXT,
      cover_url TEXT,
      has_lyrics INTEGER,
      play_count INTEGER,
      duration_ms INTEGER,
      mtime REAL,
      created_epoch_sec REAL,
      song_date_epoch_sec REAL
    )''',
    'playlist': '''CREATE TABLE IF NOT EXISTS playlist (
      id TEXT PRIMARY KEY,
      name TEXT,
      description TEXT,
      is_recommendation INTEGER DEFAULT 0,
      created_at REAL,
      updated_at REAL
    )''',
    'playlist_song': '''CREATE TABLE IF NOT EXISTS playlist_song (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id TEXT,
      song_filename TEXT,
      added_at REAL,
      FOREIGN KEY (playlist_id) REFERENCES playlist (id)
    )''',
    'merged_song_group': '''CREATE TABLE IF NOT EXISTS merged_song_group (
      id TEXT PRIMARY KEY,
      priority_filename TEXT,
      created_at REAL
    )''',
    'merged_song': '''CREATE TABLE IF NOT EXISTS merged_song (
      filename TEXT PRIMARY KEY,
      group_id TEXT,
      added_at REAL,
      FOREIGN KEY (group_id) REFERENCES merged_song_group (id) ON DELETE CASCADE
    )''',
    'recommendation_preference':
        '''CREATE TABLE IF NOT EXISTS recommendation_preference (
      id TEXT PRIMARY KEY,
      custom_title TEXT,
      is_pinned INTEGER DEFAULT 0,
      updated_at REAL
    )''',
    'recommendation_removal':
        '''CREATE TABLE IF NOT EXISTS recommendation_removal (
      id TEXT PRIMARY KEY,
      removed_at REAL
    )''',
    'mood_tag': '''CREATE TABLE IF NOT EXISTS mood_tag (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT UNIQUE NOT NULL,
      is_preset INTEGER DEFAULT 0,
      created_at REAL
    )''',
    'song_mood': '''CREATE TABLE IF NOT EXISTS song_mood (
      song_filename TEXT NOT NULL,
      mood_id TEXT NOT NULL,
      added_at REAL,
      source TEXT DEFAULT 'manual',
      PRIMARY KEY (song_filename, mood_id),
      FOREIGN KEY (mood_id) REFERENCES mood_tag (id) ON DELETE CASCADE
    )''',
  };

  /// Expected columns per table for ALTER TABLE ADD COLUMN operations.
  /// Maps table name → (column name → type fragment used in ALTER TABLE ADD COLUMN).
  static const Map<String, Map<String, String>> userDataExpectedColumns = {
    'userdata': {
      'username': 'TEXT',
      'password_hash': 'TEXT',
      'created_at': 'REAL',
    },
    'favorite': {
      'filename': 'TEXT',
      'added_at': 'REAL',
    },
    'suggestless': {
      'filename': 'TEXT',
      'added_at': 'REAL',
    },
    'hidden': {
      'filename': 'TEXT',
      'hidden_at': 'REAL',
    },
    'song': {
      'filename': 'TEXT',
      'title': 'TEXT',
      'artist': 'TEXT',
      'album': 'TEXT',
      'url': 'TEXT',
      'cover_url': 'TEXT',
      'has_lyrics': 'INTEGER',
      'play_count': 'INTEGER',
      'duration_ms': 'INTEGER',
      'mtime': 'REAL',
      'created_epoch_sec': 'REAL',
      'song_date_epoch_sec': 'REAL',
    },
    'playlist': {
      'id': 'TEXT',
      'name': 'TEXT',
      'description': 'TEXT',
      'is_recommendation': 'INTEGER DEFAULT 0',
      'created_at': 'REAL',
      'updated_at': 'REAL',
    },
    'playlist_song': {
      'id': 'INTEGER',
      'playlist_id': 'TEXT',
      'song_filename': 'TEXT',
      'added_at': 'REAL',
    },
    'merged_song_group': {
      'id': 'TEXT',
      'priority_filename': 'TEXT',
      'created_at': 'REAL',
    },
    'merged_song': {
      'filename': 'TEXT',
      'group_id': 'TEXT',
      'added_at': 'REAL',
    },
    'recommendation_preference': {
      'id': 'TEXT',
      'custom_title': 'TEXT',
      'is_pinned': 'INTEGER DEFAULT 0',
      'updated_at': 'REAL',
    },
    'recommendation_removal': {
      'id': 'TEXT',
      'removed_at': 'REAL',
    },
    'mood_tag': {
      'id': 'TEXT',
      'name': 'TEXT',
      'normalized_name': 'TEXT',
      'is_preset': 'INTEGER DEFAULT 0',
      'created_at': 'REAL',
    },
    'song_mood': {
      'song_filename': 'TEXT',
      'mood_id': 'TEXT',
      'added_at': 'REAL',
      'source': "TEXT DEFAULT 'manual'",
    },
  };

  /// Expected performance indexes for wispie_data.db, keyed by index name.
  static const Map<String, String> userDataIndexSql = {
    'idx_song_artist':
        'CREATE INDEX IF NOT EXISTS idx_song_artist ON song(artist)',
    'idx_song_album':
        'CREATE INDEX IF NOT EXISTS idx_song_album ON song(album)',
    'idx_song_mtime':
        'CREATE INDEX IF NOT EXISTS idx_song_mtime ON song(mtime)',
    'idx_song_created_epoch_sec':
        'CREATE INDEX IF NOT EXISTS idx_song_created_epoch_sec ON song(created_epoch_sec)',
    'idx_song_date_epoch_sec':
        'CREATE INDEX IF NOT EXISTS idx_song_date_epoch_sec ON song(song_date_epoch_sec)',
    'idx_song_mood_song_filename':
        'CREATE INDEX IF NOT EXISTS idx_song_mood_song_filename ON song_mood(song_filename)',
    'idx_song_mood_mood_id':
        'CREATE INDEX IF NOT EXISTS idx_song_mood_mood_id ON song_mood(mood_id)',
    'idx_mood_tag_normalized_name':
        'CREATE INDEX IF NOT EXISTS idx_mood_tag_normalized_name ON mood_tag(normalized_name)',
    'idx_merged_song_group_id':
        'CREATE INDEX IF NOT EXISTS idx_merged_song_group_id ON merged_song(group_id)',
    'idx_playlist_song_playlist_id':
        'CREATE INDEX IF NOT EXISTS idx_playlist_song_playlist_id ON playlist_song(playlist_id)',
  };

  Future<void> importData({
    required String statsDbPath,
    required String dataDbPath,
    required bool additive,
  }) async {
    await _ensureInitialized();
    final importedStatsDb = await openDatabase(statsDbPath);
    final importedDataDb = await openDatabase(dataDbPath);

    try {
      await _statsDatabase!.transaction((txn) async {
        if (!additive) {
          await txn.delete('playevent');
          await txn.delete('playsession');
        }

        // Import playsession
        final sessions = await importedStatsDb.query('playsession');
        for (final session in sessions) {
          await txn.insert('playsession', session,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Import playevent
        final events = await importedStatsDb.query('playevent');
        for (final event in events) {
          final eventMap = Map<String, dynamic>.from(event);
          eventMap.remove('id'); // Let local DB autoincrement

          if (additive) {
            // Check for duplicates: session_id, song_filename, timestamp
            final existing = await txn.query('playevent',
                where: 'session_id = ? AND song_filename = ? AND timestamp = ?',
                whereArgs: [
                  event['session_id'],
                  event['song_filename'],
                  event['timestamp']
                ]);
            if (existing.isEmpty) {
              await txn.insert('playevent', eventMap);
            }
          } else {
            await txn.insert('playevent', eventMap);
          }
        }
      });

      await _userDataDatabase!.transaction((txn) async {
        if (!additive) {
          await txn.delete('favorite');
          await txn.delete('suggestless');
          await txn.delete('hidden');
          await txn.delete('song_mood');
          await txn.delete('mood_tag');
          await txn.delete('playlist_song');
          await txn.delete('playlist');
        }

        // Import favorites
        final favorites = await importedDataDb.query('favorite');
        for (final fav in favorites) {
          await txn.insert('favorite', fav,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Import suggestless
        final suggestless = await importedDataDb.query('suggestless');
        for (final sl in suggestless) {
          await txn.insert('suggestless', sl,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Import hidden
        final hidden = await importedDataDb.query('hidden');
        for (final h in hidden) {
          await txn.insert('hidden', h,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        final hasMoodTag = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='mood_tag'");
        if (hasMoodTag.isNotEmpty) {
          final moodTags = await importedDataDb.query('mood_tag');
          for (final mood in moodTags) {
            await txn.insert('mood_tag', mood,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        final hasSongMood = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='song_mood'");
        if (hasSongMood.isNotEmpty) {
          final songMoods = await importedDataDb.query('song_mood');
          for (final sm in songMoods) {
            await txn.insert('song_mood', sm,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        // Import playlists
        final playlists = await importedDataDb.query('playlist');
        for (final pl in playlists) {
          await txn.insert('playlist', pl,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Import playlist_song
        final playlistSongs = await importedDataDb.query('playlist_song');
        for (final ps in playlistSongs) {
          final psMap = Map<String, dynamic>.from(ps);
          psMap.remove('id');
          await txn.insert('playlist_song', psMap,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Import queue history
        final hasQueueSnapshot = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='queue_snapshot'");
        if (hasQueueSnapshot.isNotEmpty) {
          if (!additive) {
            await txn.delete('queue_snapshot_song');
            await txn.delete('queue_snapshot');
          }

          final queueSnapshots = await importedDataDb.query('queue_snapshot');
          for (final snapshot in queueSnapshots) {
            final snapshotId = snapshot['id'] as String;
            final name = snapshot['name'] as String;
            final createdAt = snapshot['created_at'] as double;
            final source = snapshot['source'] as String? ?? 'imported';
            final songCount = snapshot['song_count'] as int? ?? 0;

            await txn.insert(
                'queue_snapshot',
                {
                  'id': snapshotId,
                  'name': name,
                  'created_at': createdAt,
                  'source': source,
                  'song_count': songCount,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);

            final snapshotSongs = await importedDataDb.query(
              'queue_snapshot_song',
              where: 'snapshot_id = ?',
              whereArgs: [snapshotId],
              orderBy: 'position ASC',
            );

            for (final song in snapshotSongs) {
              await txn.insert(
                  'queue_snapshot_song',
                  {
                    'snapshot_id': snapshotId,
                    'song_filename': song['song_filename'],
                    'position': song['position'],
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      });
    } finally {
      await importedStatsDb.close();
      await importedDataDb.close();
    }
  }

  void dispose() {
    _statsDatabase?.close();
    _userDataDatabase?.close();
    _statsDatabase = null;
    _userDataDatabase = null;
    _initCompleter = null;
  }

  Future<void> close() async {
    await _statsDatabase?.close();
    await _userDataDatabase?.close();
    _statsDatabase = null;
    _userDataDatabase = null;
    _initCompleter = null;
  }
}

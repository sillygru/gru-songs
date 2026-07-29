import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/playlist.dart';
import '../models/queue_snapshot.dart';
import '../models/song.dart';
import 'import_options.dart';
import 'sync_service.dart';
import 'wispie_paths.dart';

/// DatabaseService handles local SQLite storage.
class DatabaseService {
  static const double _skipRatioThreshold = 0.25;

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

  Future<void> init() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();

    try {
      // Open local databases (create schema if needed)
      _statsDatabase = await _openDatabase('wispie_stats.db', _statsSchema);
      _userDataDatabase =
          await _openDatabase('wispie_data.db', _userDataSchema);

      // Ensure tables and columns exist
      await _ensureStatsTables(_statsDatabase!);
      await _ensureTablesAndColumns(_userDataDatabase!);

      _initCompleter!.complete();
    } catch (e) {
      debugPrint('Database initialization failed: $e');
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _ensureStatsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playsession (
        id TEXT PRIMARY KEY,
        start_time REAL,
        end_time REAL,
        platform TEXT,
        device_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playevent (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        song_filename TEXT,
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
    // 1. Ensure Tables exist
    await db.execute(
        'CREATE TABLE IF NOT EXISTS favorite (filename TEXT PRIMARY KEY, added_at REAL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS suggestless (filename TEXT PRIMARY KEY, added_at REAL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS hidden (filename TEXT PRIMARY KEY, hidden_at REAL)');
    // Negative cache for cover art. Without it, a song that genuinely has no
    // artwork is re-probed (whole-file byte scan + FFmpeg) every time a list
    // tile for it is built.
    await db.execute(
        'CREATE TABLE IF NOT EXISTS cover_miss (filename TEXT PRIMARY KEY, file_mtime REAL, checked_at REAL)');
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
    await db.execute('''
        CREATE TABLE IF NOT EXISTS artist_art (
          artist_name TEXT PRIMARY KEY,
          image_url TEXT,
          local_path TEXT,
          source TEXT,
          updated_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS album_art (
          album_key TEXT PRIMARY KEY,
          album_name TEXT,
          artist_name TEXT,
          image_url TEXT,
          local_path TEXT,
          source TEXT,
          updated_at REAL
        )
    ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS translated_lyrics (
          filename TEXT,
          target_lang TEXT,
          translated_content TEXT,
          updated_at REAL,
          PRIMARY KEY (filename, target_lang)
        )
    ''');

    // 2. Create indexes for the song table
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
        'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_created_at ON queue_snapshot(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_queue_snapshot_song_snapshot_id ON queue_snapshot_song(snapshot_id)');
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
    final wispieDir = await getWispieDirectory();
    final path = join(wispieDir.path, name);
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

  Future<List<QueueSnapshot>> getQueueHistorySnapshots() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];

    try {
      return await _userDataDatabase!.transaction((txn) async {
        final snapshots = await txn.query(
          'queue_snapshot',
          orderBy: 'created_at DESC',
        );
        if (snapshots.isEmpty) return [];

        final snapshotIds =
            snapshots.map((row) => row['id'] as String).toList();
        final placeholders = List.filled(snapshotIds.length, '?').join(',');
        final songRows = await txn.rawQuery(
          '''
          SELECT snapshot_id, song_filename
          FROM queue_snapshot_song
          WHERE snapshot_id IN ($placeholders)
          ORDER BY snapshot_id ASC, position ASC
          ''',
          snapshotIds,
        );

        final songsBySnapshot = <String, List<String>>{};
        for (final row in songRows) {
          final snapshotId = row['snapshot_id'] as String;
          final songFilename = row['song_filename'] as String;
          songsBySnapshot.putIfAbsent(snapshotId, () => <String>[]).add(
                songFilename,
              );
        }

        final seenFingerprints = <String>{};
        final result = <QueueSnapshot>[];

        for (final row in snapshots) {
          final createdAtRaw = row['created_at'];
          final createdAt = createdAtRaw is num
              ? createdAtRaw.toDouble()
              : double.tryParse(createdAtRaw?.toString() ?? '') ??
                  DateTime.now().millisecondsSinceEpoch / 1000.0;
          final id = row['id'] as String;
          final nameRaw = row['name']?.toString();
          final name = (nameRaw != null && nameRaw.trim().isNotEmpty)
              ? nameRaw.trim()
              : QueueSnapshot.defaultNameForTimestamp(createdAt);

          final source = row['source'] as String? ?? 'unknown';
          final filenames = songsBySnapshot[id] ?? const <String>[];
          final fingerprint = _queueSnapshotFingerprint(source, filenames);
          if (seenFingerprints.contains(fingerprint)) continue;
          seenFingerprints.add(fingerprint);

          result.add(QueueSnapshot(
            id: id,
            name: name,
            createdAt: createdAt,
            songFilenames: filenames,
            source: source,
          ));
        }

        return result;
      });
    } catch (e) {
      debugPrint('Error loading queue history snapshots: $e');
      return [];
    }
  }

  String _queueSnapshotFingerprint(String source, List<String> filenames) {
    return '$source\u0000${filenames.join('\u0000')}';
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

  // Keep the queue history table from growing unbounded. Caller invokes
  // this after inserting a new snapshot. We retain the most recent N
  // snapshots by created_at and drop older ones in a single transaction.
  static const int _maxQueueSnapshotsRetained = 50;

  Future<void> pruneQueueSnapshots() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT id FROM queue_snapshot ORDER BY created_at DESC '
        'LIMIT -1 OFFSET ?',
        [_maxQueueSnapshotsRetained],
      );
      if (rows.isEmpty) return;
      final ids = rows.map((r) => r['id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await txn.delete('queue_snapshot_song',
          where: 'snapshot_id IN ($placeholders)', whereArgs: ids);
      await txn.delete('queue_snapshot',
          where: 'id IN ($placeholders)', whereArgs: ids);
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
        final createdAtRaw = snapshot['created_at'];
        final createdAt = createdAtRaw is num
            ? createdAtRaw.toDouble()
            : double.tryParse(createdAtRaw?.toString() ?? '') ??
                DateTime.now().millisecondsSinceEpoch / 1000.0;
        final snapshotIdRaw = snapshot['id']?.toString();
        final snapshotId =
            (snapshotIdRaw != null && snapshotIdRaw.trim().isNotEmpty)
                ? snapshotIdRaw.trim()
                : QueueSnapshot.timestampMarkerFromEpochSeconds(createdAt);
        final nameRaw = snapshot['name']?.toString();
        final name = (nameRaw != null && nameRaw.trim().isNotEmpty)
            ? nameRaw.trim()
            : QueueSnapshot.defaultNameForTimestamp(createdAt);
        final source = snapshot['source'] as String? ?? 'imported';
        final songs = (snapshot['songs'] as List?)
                ?.map((song) => song.toString())
                .toList() ??
            [];

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

  /// Upserts library rows, keyed by [Song.filename].
  ///
  /// With [preserveCoverUrl] — the default — a null incoming `cover_url` leaves
  /// whatever the row already had. That guard is deliberately at this level
  /// rather than in each caller: a scan that couldn't read a file, a cover
  /// rebuild that couldn't resolve one, and an import carrying another device's
  /// rows all produce nulls, and any one of them silently erasing working
  /// artwork is the bug this exists to make unrepresentable. `created_epoch_sec`
  /// is protected the same way so "date added" survives a rescan.
  ///
  /// Only [LibraryRepairService] passes false, because clearing a `cover_url`
  /// that no longer resolves is exactly its job — a null there is a considered
  /// decision, not a failure to look.
  Future<void> insertSongsBatch(
    List<Song> songs, {
    bool preserveCoverUrl = true,
  }) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;

    await _userDataDatabase!.transaction((txn) async {
      final batch = txn.batch();
      for (final song in songs) {
        final values = <String, Object?>{
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
        };

        if (!preserveCoverUrl) {
          batch.insert('song', values,
              conflictAlgorithm: ConflictAlgorithm.replace);
          continue;
        }

        final columns = values.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        final assignments = <String>[];
        for (final column in columns) {
          if (column == 'filename') continue;
          if (column == 'cover_url' || column == 'created_epoch_sec') {
            // COALESCE order differs on purpose: a new cover wins over the old
            // one, but the earliest known "date added" wins over a later scan.
            assignments.add(column == 'cover_url'
                ? 'cover_url = COALESCE(excluded.cover_url, song.cover_url)'
                : 'created_epoch_sec = COALESCE(song.created_epoch_sec, excluded.created_epoch_sec)');
            continue;
          }
          assignments.add('$column = excluded.$column');
        }

        batch.rawInsert(
          'INSERT INTO song (${columns.join(', ')}) VALUES ($placeholders) '
          'ON CONFLICT(filename) DO UPDATE SET ${assignments.join(', ')}',
          columns.map((c) => values[c]).toList(),
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Songs already probed for cover art and found to have none, keyed by
  /// filename with the file mtime at the time of the probe. A changed mtime
  /// means the file was edited and is worth probing again.
  Future<Map<String, double>> getCoverMisses() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return {};
    final results = await _userDataDatabase!
        .query('cover_miss', columns: ['filename', 'file_mtime']);
    return {
      for (final row in results)
        row['filename'] as String: (row['file_mtime'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> markCoverMiss(String filename, double fileMtime) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.insert(
      'cover_miss',
      {
        'filename': filename,
        'file_mtime': fileMtime,
        'checked_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearCoverMiss(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!
        .delete('cover_miss', where: 'filename = ?', whereArgs: [filename]);
  }

  /// Forgets the negative cache entirely.
  ///
  /// Every entry records "this file had no art" as observed on some device at
  /// some time. After a restore or a cover-cache wipe none of that is still
  /// trustworthy, and re-probing is precisely the behaviour we want back.
  Future<void> clearAllCoverMisses() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    await _userDataDatabase!.delete('cover_miss');
  }

  Future<void> clearCoverMisses(Iterable<String> filenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    final list = filenames.toList();
    if (list.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final chunk in _chunked(list)) {
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.delete('cover_miss',
            where: 'filename IN ($placeholders)', whereArgs: chunk);
      }
    });
  }

  /// Drops every cached cover path without touching the files.
  ///
  /// Pairs with deleting the cover directory: leaving the paths behind is what
  /// makes a "clear cover cache" look like it did nothing, because every row
  /// still points at a hole instead of being null enough for the lazy
  /// extraction path to take over.
  Future<int> clearCoverUrls() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return 0;
    return _userDataDatabase!.rawUpdate(
        'UPDATE song SET cover_url = NULL WHERE cover_url IS NOT NULL');
  }

  Future<void> deleteSongsByFilenames(Iterable<String> filenames) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return;
    final list = filenames.toList();
    if (list.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final chunk in _chunked(list)) {
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await txn.delete('song',
            where: 'filename IN ($placeholders)', whereArgs: chunk);
      }
    });
  }

  /// SQLite caps a statement at 999 variables by default; stay well under it.
  static Iterable<List<String>> _chunked(List<String> values,
      {int size = 500}) sync* {
    for (var i = 0; i < values.length; i += size) {
      yield values.sublist(i, min(i + size, values.length));
    }
  }

  Future<List<Song>> getAllSongs() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final results = await _userDataDatabase!.query('song');
    return results.map((r) => _mapToSong(r)).toList();
  }

  Future<Song?> getSongByFilename(String filename) async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return null;
    final results = await _userDataDatabase!.query(
      'song',
      where: 'filename = ?',
      whereArgs: [filename],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return _mapToSong(results.first);
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
        if (entry.value.length >= 2) {
          result[entry.key] = (
            filenames: entry.value,
            priorityFilename: groupPriorities[entry.key],
          );
        }
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

    final groupId = const Uuid().v4();
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
      await _cleanupSingleSongGroups(txn);
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
      await _cleanupSingleSongGroups(txn);
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

      await _cleanupSingleSongGroups(txn);
    });

    debugPrint('Removed $filename from merged group');
  }

  Future<void> _cleanupSingleSongGroups(Transaction txn) async {
    final results = await txn.rawQuery('''
      SELECT group_id, COUNT(*) as song_count
      FROM merged_song
      GROUP BY group_id
      HAVING song_count < 2
    ''');
    for (final row in results) {
      final groupId = row['group_id'] as String;
      await txn
          .delete('merged_song', where: 'group_id = ?', whereArgs: [groupId]);
      await txn
          .delete('merged_song_group', where: 'id = ?', whereArgs: [groupId]);
    }
    await txn.delete('merged_song_group',
        where:
            'id NOT IN (SELECT DISTINCT group_id FROM merged_song WHERE group_id IS NOT NULL)');
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

  Future<Map<String, double>> getLastPlayedTimestamps() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return {};
    try {
      final results = await _statsDatabase!.rawQuery(
          'SELECT song_filename, MAX(timestamp) as last_played FROM playevent WHERE play_ratio > 0.25 GROUP BY song_filename');
      return {
        for (var r in results)
          r['song_filename'] as String: r['last_played'] as double,
      };
    } catch (e) {
      debugPrint('Error fetching last played timestamps: $e');
      return {};
    }
  }

  /// Raw play events for affinity scoring, newest first.
  ///
  /// Unlike [getPlayHistory] this is not capped at a small recent window — the
  /// affinity model needs the whole decay horizon to tell a song someone still
  /// loves from one they burned out on a year ago. Events older than
  /// [sinceDays] contribute so little after decay that fetching them is waste.
  Future<List<({String filename, double timestamp, double playRatio})>>
      getAffinityEvents({int sinceDays = 365}) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return [];
    try {
      final cutoff = DateTime.now()
              .subtract(Duration(days: sinceDays))
              .millisecondsSinceEpoch /
          1000.0;
      final results = await _statsDatabase!.rawQuery(
        'SELECT song_filename, timestamp, play_ratio, duration_played, total_length '
        'FROM playevent WHERE timestamp >= ? ORDER BY timestamp DESC',
        [cutoff],
      );

      final events =
          <({String filename, double timestamp, double playRatio})>[];
      for (final r in results) {
        final filename = r['song_filename'] as String?;
        final timestamp = (r['timestamp'] as num?)?.toDouble();
        if (filename == null || timestamp == null) continue;

        // Same fallback as getPlayHistory: older rows can predate play_ratio.
        final duration = (r['duration_played'] as num?)?.toDouble() ?? 0.0;
        final totalLength = (r['total_length'] as num?)?.toDouble() ?? 0.0;
        final playRatio = (r['play_ratio'] as num?)?.toDouble() ??
            (totalLength > 0 ? duration / totalLength : 0.0);

        events.add((
          filename: filename,
          timestamp: timestamp,
          playRatio: playRatio,
        ));
      }
      return events;
    } catch (e) {
      debugPrint('Error fetching affinity events: $e');
      return [];
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

  Future<void> insertPlayEvent(Map<String, dynamic> event,
      {bool isSync = false}) async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;

    await _statsDatabase!.transaction((txn) async {
      await _insertPlayEventTxn(txn, event, isSync: isSync);
    });
  }

  Future<void> insertPlayEventsBatch(List<Map<String, dynamic>> events,
      {bool isSync = false}) async {
    await _ensureInitialized();
    if (_statsDatabase == null || events.isEmpty) return;

    await _statsDatabase!.transaction((txn) async {
      for (final event in events) {
        await _insertPlayEventTxn(txn, event, isSync: isSync);
      }
    });
  }

  String _classifyPlayEventType(double playRatio) {
    return playRatio < _skipRatioThreshold ? 'skip' : 'listen';
  }

  Future<void> _insertPlayEventTxn(Transaction txn, Map<String, dynamic> event,
      {bool isSync = false}) async {
    final sessionId = event['session_id'] as String?;
    final songFilename = event['song_filename'] as String?;
    final timestamp = (event['timestamp'] as num?)?.toDouble();
    if (sessionId == null || sessionId.isEmpty) {
      throw ArgumentError('session_id is required');
    }
    if (songFilename == null || songFilename.isEmpty) {
      throw ArgumentError('song_filename is required');
    }
    if (timestamp == null) {
      throw ArgumentError('timestamp is required');
    }

    final deviceId = event['device_id'] as String?;

    await txn.insert(
        'playsession',
        {
          'id': sessionId,
          'start_time': timestamp,
          'end_time': timestamp,
          'platform': event['platform'] ?? 'unknown',
          'device_id': deviceId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    if (deviceId != null && deviceId.isNotEmpty) {
      await txn.rawUpdate(
          'UPDATE playsession SET device_id = ? WHERE id = ? AND (device_id IS NULL OR device_id = \'\')',
          [deviceId, sessionId]);
    }

    await txn.rawUpdate(
        'UPDATE playsession SET end_time = ? WHERE id = ? AND end_time < ?',
        [timestamp, sessionId, timestamp]);

    // Coalesce logic (Fix for fragmented stats)
    final lastEvents = await txn.query(
      'playevent',
      where: 'session_id = ? AND song_filename = ?',
      whereArgs: [sessionId, songFilename],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    final totalLength = (event['total_length'] as num?)?.toDouble() ?? 0.0;
    final duration = (event['duration_played'] as num?)?.toDouble() ?? 0.0;
    final incomingRatio = (event['play_ratio'] as num?)?.toDouble() ??
        (totalLength > 0 ? duration / totalLength : 0.0);
    final incomingFg =
        (event['foreground_duration'] as num?)?.toDouble() ?? 0.0;
    final incomingBg =
        (event['background_duration'] as num?)?.toDouble() ?? 0.0;

    if (lastEvents.isNotEmpty) {
      final last = lastEvents.first;
      final lastId = last['id'] as int;
      final lastTotalLength = (last['total_length'] as num?)?.toDouble() ?? 0.0;
      final effectiveTotalLength =
          totalLength > 0 ? totalLength : lastTotalLength;

      if (isSync) {
        // Synced play events are complete point-in-time snapshots, NOT incremental diffs.
        // Take the maximum values rather than blindly adding durations which inflates stats.
        final lastDuration =
            (last['duration_played'] as num?)?.toDouble() ?? 0.0;
        final lastFg = (last['foreground_duration'] as num?)?.toDouble() ?? 0.0;
        final lastBg = (last['background_duration'] as num?)?.toDouble() ?? 0.0;
        final lastRatio = (last['play_ratio'] as num?)?.toDouble() ?? 0.0;
        final lastTimestamp = (last['timestamp'] as num?)?.toDouble() ?? 0.0;

        double newDuration = max(lastDuration, duration);
        if (effectiveTotalLength > 0 &&
            newDuration > effectiveTotalLength * 1.05 + 10.0) {
          newDuration = effectiveTotalLength;
        }

        final newFg = max(lastFg, incomingFg);
        final newBg = max(lastBg, incomingBg);
        final newRatio = effectiveTotalLength > 0
            ? min(1.0, newDuration / effectiveTotalLength)
            : max(lastRatio, incomingRatio);
        final newTimestamp = max(lastTimestamp, timestamp);

        await txn.update(
            'playevent',
            {
              'duration_played': newDuration,
              'foreground_duration': newFg,
              'background_duration': newBg,
              'total_length': effectiveTotalLength,
              'timestamp': newTimestamp,
              'play_ratio': newRatio,
            },
            where: 'id = ?',
            whereArgs: [lastId]);
      } else {
        // Live playback incremental flush on local player
        double newDuration =
            (last['duration_played'] as num).toDouble() + duration;
        double newFg =
            ((last['foreground_duration'] as num?) ?? 0) + incomingFg;
        double newBg =
            ((last['background_duration'] as num?) ?? 0) + incomingBg;

        if (effectiveTotalLength > 0 &&
            newDuration > effectiveTotalLength * 1.05 + 10.0) {
          newDuration = effectiveTotalLength;
          if (newFg + newBg > 0) {
            final scale = newDuration / (newFg + newBg);
            newFg *= scale;
            newBg *= scale;
          }
        }

        final newRatio = effectiveTotalLength > 0
            ? min(1.0, newDuration / effectiveTotalLength)
            : incomingRatio;

        await txn.update(
            'playevent',
            {
              'duration_played': newDuration,
              'foreground_duration': newFg,
              'background_duration': newBg,
              'total_length': effectiveTotalLength,
              'timestamp': timestamp,
              'play_ratio': newRatio,
            },
            where: 'id = ?',
            whereArgs: [lastId]);
      }
    } else {
      // First insert for this song/session
      double sanitizedDuration = duration;
      double sanitizedRatio = incomingRatio;
      if (totalLength > 0 && sanitizedDuration > totalLength * 1.05 + 10.0) {
        sanitizedDuration = totalLength;
        sanitizedRatio = 1.0;
      }

      await txn.insert('playevent', {
        'session_id': sessionId,
        'song_filename': songFilename,
        'timestamp': timestamp,
        'duration_played': sanitizedDuration,
        'total_length': totalLength,
        'play_ratio': sanitizedRatio,
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

      final history = <({
        String filename,
        double timestamp,
        double playRatio,
        String eventType
      })>[];

      for (final e in events) {
        final filename = e['song_filename'] as String?;
        final timestamp = (e['timestamp'] as num?)?.toDouble();
        if (filename == null || timestamp == null) continue;

        final duration = (e['duration_played'] as num?)?.toDouble() ?? 0.0;
        final totalLength = (e['total_length'] as num?)?.toDouble() ?? 0.0;
        final playRatio = (e['play_ratio'] as num?)?.toDouble() ??
            (totalLength > 0 ? duration / totalLength : 0.0);

        history.add((
          filename: filename,
          timestamp: timestamp,
          playRatio: playRatio,
          eventType: _classifyPlayEventType(playRatio),
        ));
      }

      return history;
    } catch (e) {
      debugPrint('Error getting play history: $e');
      return [];
    }
  }

  /// Repairs corrupted playevent rows where duration_played was inflated beyond
  /// actual song lengths (e.g. from repeated sync compounding).
  Future<int> repairCorruptedPlayStats() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return 0;

    int repairedCount = 0;
    try {
      final songs = await getAllSongs();
      final songDurationMap = {
        for (var s in songs)
          if (s.duration != null && s.duration!.inMilliseconds > 0)
            s.filename: s.duration!.inMilliseconds / 1000.0
      };

      final corruptedEvents = await _statsDatabase!.rawQuery('''
        SELECT id, song_filename, duration_played, total_length, foreground_duration, background_duration
        FROM playevent
      ''');

      await _statsDatabase!.transaction((txn) async {
        for (final row in corruptedEvents) {
          final id = row['id'] as int;
          final filename = row['song_filename'] as String? ?? '';
          final durationPlayed =
              (row['duration_played'] as num?)?.toDouble() ?? 0.0;
          var totalLength = (row['total_length'] as num?)?.toDouble() ?? 0.0;

          if (totalLength <= 0 && songDurationMap.containsKey(filename)) {
            totalLength = songDurationMap[filename]!;
          }

          bool needsRepair = false;
          double targetDuration = durationPlayed;

          if (totalLength > 0 && durationPlayed > totalLength * 1.01) {
            needsRepair = true;
            targetDuration = totalLength;
          } else if (totalLength <= 0 && durationPlayed > 600.0) {
            // Cap orphan songs with no length metadata at 10 minutes max per play
            needsRepair = true;
            targetDuration = 600.0;
          }

          if (needsRepair) {
            repairedCount++;
            final fg = (row['foreground_duration'] as num?)?.toDouble() ?? 0.0;
            final bg = (row['background_duration'] as num?)?.toDouble() ?? 0.0;
            double newFg = fg;
            double newBg = bg;
            if (fg + bg > 0) {
              final scale = targetDuration / (fg + bg);
              newFg = fg * scale;
              newBg = bg * scale;
            } else {
              newFg = targetDuration;
            }

            final newRatio =
                totalLength > 0 ? min(1.0, targetDuration / totalLength) : 1.0;

            await txn.update(
              'playevent',
              {
                'duration_played': targetDuration,
                'total_length': totalLength > 0 ? totalLength : 0.0,
                'foreground_duration': newFg,
                'background_duration': newBg,
                'play_ratio': newRatio,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      });

      if (repairedCount > 0) {
        debugPrint('Repaired $repairedCount corrupted playevent rows.');
      }
    } catch (e) {
      debugPrint('Error repairing corrupted play stats: $e');
    }
    return repairedCount;
  }

  Future<Map<String, dynamic>> getFunStats() async {
    await _ensureInitialized();

    if (_statsDatabase == null) {
      return {"stats": []};
    }

    try {
      await repairCorruptedPlayStats();
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

        final ratio = (event['play_ratio'] as num?)?.toDouble() ??
            (duration > 0 && (event['total_length'] as num?)?.toDouble() != null
                ? duration / (event['total_length'] as num).toDouble()
                : 0.0);

        final filename = event['song_filename'] as String;

        final timestamp = (event['timestamp'] as num).toDouble();

        totalTimeSeconds += duration;

        final dt =
            DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());

        playDates.add(DateTime(dt.year, dt.month, dt.day));

        hourCounts[dt.hour] = (hourCounts[dt.hour] ?? 0) + 1;

        final dayName = _getDayName(dt.weekday);

        dayCounts[dayName] = (dayCounts[dayName] ?? 0) + 1;

        if (duration > 10 || ratio > 0.25) {
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

        if (duration < 10 && ratio < 0.25) {
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

      // 7. Skips (calculated from duration: listened < 10s and ratio < 0.25)
      stats.add({
        "id": "skips",
        "label": "Quick Skips",
        "value": totalSkips.toString(),
        "subtitle": "Songs skipped quickly."
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
      platform TEXT,
      device_id TEXT
    );
    CREATE TABLE IF NOT EXISTS playevent (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      song_filename TEXT,
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
  ''';

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
          await txn.delete('userdata');
          await txn.delete('recommendation_preference');
          await txn.delete('recommendation_removal');
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

        // Import userdata
        final hasUserdata = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='userdata'");
        if (hasUserdata.isNotEmpty) {
          final userdata = await importedDataDb.query('userdata');
          for (final ud in userdata) {
            await txn.insert('userdata', ud,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // Import recommendation_preference
        final hasRecPref = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='recommendation_preference'");
        if (hasRecPref.isNotEmpty) {
          final recPrefs =
              await importedDataDb.query('recommendation_preference');
          for (final pref in recPrefs) {
            await txn.insert('recommendation_preference', pref,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // Import recommendation_removal
        final hasRecRem = await importedDataDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='recommendation_removal'");
        if (hasRecRem.isNotEmpty) {
          final recRemovals =
              await importedDataDb.query('recommendation_removal');
          for (final rem in recRemovals) {
            await txn.insert('recommendation_removal', rem,
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
            final createdAtRaw = snapshot['created_at'];
            final createdAt = createdAtRaw is num
                ? createdAtRaw.toDouble()
                : double.tryParse(createdAtRaw?.toString() ?? '') ??
                    DateTime.now().millisecondsSinceEpoch / 1000.0;
            final snapshotIdRaw = snapshot['id']?.toString();
            final snapshotId =
                (snapshotIdRaw != null && snapshotIdRaw.trim().isNotEmpty)
                    ? snapshotIdRaw.trim()
                    : QueueSnapshot.timestampMarkerFromEpochSeconds(createdAt);
            final nameRaw = snapshot['name']?.toString();
            final name = (nameRaw != null && nameRaw.trim().isNotEmpty)
                ? nameRaw.trim()
                : QueueSnapshot.defaultNameForTimestamp(createdAt);
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

  Future<void> importWithOptions({
    required String statsDbPath,
    required String dataDbPath,
    required ImportOptions options,
  }) async {
    await _ensureInitialized();
    final importedStatsDb = await openDatabase(statsDbPath);
    final importedDataDb = await openDatabase(dataDbPath);

    try {
      if (options.hasDatabaseCategories) {
        await _importSelectedDatabases(
            importedStatsDb, importedDataDb, options);
      }
    } finally {
      await importedStatsDb.close();
      await importedDataDb.close();
    }
  }

  Future<void> _importSelectedDatabases(
    Database importedStatsDb,
    Database importedDataDb,
    ImportOptions options,
  ) async {
    final categories = options.categories;
    final additive = options.additive;

    if (categories.contains(ImportDataCategory.playHistory)) {
      await _importPlayHistory(importedStatsDb, additive);
    }

    if (categories.contains(ImportDataCategory.favorites)) {
      await _importFavorites(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.suggestless)) {
      await _importSuggestless(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.hidden)) {
      await _importHidden(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.userdata)) {
      await _importUserdata(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.recommendations)) {
      await _importRecommendations(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.playlists)) {
      await _importPlaylists(importedDataDb, additive);
    }
    if (categories.contains(ImportDataCategory.mergedGroups)) {
      await _importMergedGroups(importedDataDb, additive);
    }
    await _importArtistAlbumArt(importedDataDb, additive);
  }

  Future<void> _importPlayHistory(Database importedDb, bool additive) async {
    await _statsDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('playevent');
        await txn.delete('playsession');
      }

      final sessions = await importedDb.query('playsession');
      for (final session in sessions) {
        await txn.insert('playsession', session,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final events = await importedDb.query('playevent');
      for (final event in events) {
        final eventMap = Map<String, dynamic>.from(event);
        eventMap.remove('id');

        if (additive) {
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
  }

  Future<void> _importFavorites(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('favorite');
      }

      final favorites = await importedDb.query('favorite');
      for (final fav in favorites) {
        await txn.insert('favorite', fav,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _importSuggestless(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('suggestless');
      }

      final suggestless = await importedDb.query('suggestless');
      for (final sl in suggestless) {
        await txn.insert('suggestless', sl,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _importHidden(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('hidden');
      }

      final hidden = await importedDb.query('hidden');
      for (final h in hidden) {
        await txn.insert('hidden', h,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _importUserdata(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('userdata');
      }

      final hasUserdata = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='userdata'");
      if (hasUserdata.isNotEmpty) {
        final userdata = await importedDb.query('userdata');
        for (final ud in userdata) {
          await txn.insert('userdata', ud,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> _importRecommendations(
      Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('recommendation_preference');
        await txn.delete('recommendation_removal');
      }

      final hasRecPref = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recommendation_preference'");
      if (hasRecPref.isNotEmpty) {
        final recPrefs = await importedDb.query('recommendation_preference');
        for (final pref in recPrefs) {
          await txn.insert('recommendation_preference', pref,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final hasRecRem = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recommendation_removal'");
      if (hasRecRem.isNotEmpty) {
        final recRemovals = await importedDb.query('recommendation_removal');
        for (final rem in recRemovals) {
          await txn.insert('recommendation_removal', rem,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<void> _importPlaylists(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('playlist_song');
        await txn.delete('playlist');
      }

      final playlists = await importedDb.query('playlist');
      for (final pl in playlists) {
        await txn.insert('playlist', pl,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final playlistSongs = await importedDb.query('playlist_song');
      for (final ps in playlistSongs) {
        final psMap = Map<String, dynamic>.from(ps);
        psMap.remove('id');
        await txn.insert('playlist_song', psMap,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _importMergedGroups(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('merged_song');
        await txn.delete('merged_song_group');
      }

      final hasMergedGroup = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='merged_song_group'");
      if (hasMergedGroup.isNotEmpty) {
        final mergedGroups = await importedDb.query('merged_song_group');
        for (final group in mergedGroups) {
          await txn.insert('merged_song_group', group,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        final mergedSongs = await importedDb.query('merged_song');
        for (final song in mergedSongs) {
          await txn.insert('merged_song', song,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<void> _importArtistAlbumArt(Database importedDb, bool additive) async {
    await _userDataDatabase!.transaction((txn) async {
      if (!additive) {
        await txn.delete('artist_art');
        await txn.delete('album_art');
      }

      final hasArtistArt = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='artist_art'");
      if (hasArtistArt.isNotEmpty) {
        final rows = await importedDb.query('artist_art');
        for (final r in rows) {
          await txn.insert('artist_art', r,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final hasAlbumArt = await importedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='album_art'");
      if (hasAlbumArt.isNotEmpty) {
        final rows = await importedDb.query('album_art');
        for (final r in rows) {
          await txn.insert('album_art', r,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // --- Artist & Album Art Cache Methods ---

  Future<Map<String, String>> getArtistArtMap() async {
    await _ensureInitialized();
    final List<Map<String, dynamic>> maps =
        await _userDataDatabase!.query('artist_art');
    final result = <String, String>{};
    for (final map in maps) {
      final name = map['artist_name'] as String?;
      final path = map['local_path'] as String?;
      if (name != null && path != null && name.isNotEmpty && path.isNotEmpty) {
        result[name.toLowerCase()] = path;
      }
    }
    return result;
  }

  Future<void> saveArtistArt({
    required String artistName,
    required String localPath,
    String? imageUrl,
    String? source,
  }) async {
    await _ensureInitialized();
    await _userDataDatabase!.insert(
      'artist_art',
      {
        'artist_name': artistName,
        'image_url': imageUrl,
        'local_path': localPath,
        'source': source,
        'updated_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteArtistArt(String artistName) async {
    await _ensureInitialized();
    await _userDataDatabase!.delete(
      'artist_art',
      where: 'LOWER(artist_name) = ?',
      whereArgs: [artistName.toLowerCase()],
    );
  }

  Future<void> clearArtistArt() async {
    await _ensureInitialized();
    await _userDataDatabase!.delete('artist_art');
  }

  Future<Map<String, String>> getAlbumArtMap() async {
    await _ensureInitialized();
    final List<Map<String, dynamic>> maps =
        await _userDataDatabase!.query('album_art');
    final result = <String, String>{};
    for (final map in maps) {
      final key = map['album_key'] as String?;
      final path = map['local_path'] as String?;
      if (key != null && path != null && key.isNotEmpty && path.isNotEmpty) {
        result[key.toLowerCase()] = path;
      }
    }
    return result;
  }

  Future<void> saveAlbumArt({
    required String albumKey,
    required String albumName,
    String? artistName,
    required String localPath,
    String? imageUrl,
    String? source,
  }) async {
    await _ensureInitialized();
    await _userDataDatabase!.insert(
      'album_art',
      {
        'album_key': albumKey,
        'album_name': albumName,
        'artist_name': artistName,
        'image_url': imageUrl,
        'local_path': localPath,
        'source': source,
        'updated_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAlbumArt(String albumKey) async {
    await _ensureInitialized();
    await _userDataDatabase!.delete(
      'album_art',
      where: 'LOWER(album_key) = ?',
      whereArgs: [albumKey.toLowerCase()],
    );
  }

  Future<void> clearAlbumArt() async {
    await _ensureInitialized();
    await _userDataDatabase!.delete('album_art');
  }

  // ==========================================================================
  // SYNC DATA EXPORT METHODS
  // ==========================================================================

  Future<List<Map<String, dynamic>>> getPlayEventsForSync() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return [];
    final currentDeviceId = SyncService.instance.deviceId;
    final results = await _statsDatabase!.rawQuery('''
      SELECT pe.*, COALESCE(NULLIF(ps.device_id, ''), ?) AS device_id, ps.platform
      FROM playevent pe
      LEFT JOIN playsession ps ON pe.session_id = ps.id
    ''', [currentDeviceId]);
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<Map<String, int>> getPlayStatsDeviceBreakdown(
      String currentDeviceId) async {
    await _ensureInitialized();
    if (_statsDatabase == null) {
      return {'localPlayCount': 0, 'remotePlayCount': 0, 'totalPlayCount': 0};
    }
    final results = await _statsDatabase!.rawQuery('''
      SELECT 
        COALESCE(ps.device_id, ?) AS dev_id,
        COUNT(pe.id) AS event_count
      FROM playevent pe
      LEFT JOIN playsession ps ON pe.session_id = ps.id
      GROUP BY dev_id
    ''', [currentDeviceId]);

    int localCount = 0;
    int remoteCount = 0;
    int totalCount = 0;

    for (final row in results) {
      final devId = row['dev_id'] as String?;
      final count = (row['event_count'] as num?)?.toInt() ?? 0;
      totalCount += count;
      if (devId == null || devId == currentDeviceId || devId == 'unknown') {
        localCount += count;
      } else {
        remoteCount += count;
      }
    }

    return {
      'localPlayCount': localCount,
      'remotePlayCount': remoteCount,
      'totalPlayCount': totalCount,
    };
  }

  Future<void> clearAllPlayStats() async {
    await _ensureInitialized();
    if (_statsDatabase == null) return;
    await _statsDatabase!.transaction((txn) async {
      await txn.delete('playevent');
      await txn.delete('playsession');
    });
  }

  Future<List<Map<String, dynamic>>> getFavoritesWithTimestamps() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    return await _userDataDatabase!.query('favorite');
  }

  Future<List<Map<String, dynamic>>> getSuggestLessWithTimestamps() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    return await _userDataDatabase!.query('suggestless');
  }

  Future<List<Map<String, dynamic>>> getHiddenWithTimestamps() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    return await _userDataDatabase!.query('hidden');
  }

  Future<List<Map<String, dynamic>>> getPlaylistsForSync() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final plMaps = await _userDataDatabase!.query('playlist');
      final result = <Map<String, dynamic>>[];
      for (final pl in plMaps) {
        final songs = await _userDataDatabase!.query(
          'playlist_song',
          where: 'playlist_id = ?',
          whereArgs: [pl['id']],
        );
        pl['songs'] = songs;
        result.add(pl);
      }
      return result;
    } catch (e) {
      debugPrint('Error exporting playlists for sync: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMergedGroupsForSync() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    try {
      final groups = await _userDataDatabase!.query('merged_song_group');
      final result = <Map<String, dynamic>>[];
      for (final g in groups) {
        final songs = await _userDataDatabase!.query(
          'merged_song',
          where: 'group_id = ?',
          whereArgs: [g['id']],
        );
        g['songs'] = songs;
        result.add(g);
      }
      return result;
    } catch (e) {
      debugPrint('Error exporting merged groups for sync: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getArtistArtForSync() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final rows = await _userDataDatabase!.query(
      'artist_art',
      where: "(image_url IS NOT NULL AND image_url != '') OR source = 'song'",
    );
    return rows.map((row) {
      final m = Map<String, dynamic>.from(row);
      m.remove('local_path');
      return m;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getAlbumArtForSync() async {
    await _ensureInitialized();
    if (_userDataDatabase == null) return [];
    final rows = await _userDataDatabase!.query(
      'album_art',
      where: "(image_url IS NOT NULL AND image_url != '') OR source = 'song'",
    );
    return rows.map((row) {
      final m = Map<String, dynamic>.from(row);
      m.remove('local_path');
      return m;
    }).toList();
  }

  // ==========================================================================
  // SYNC DATA IMPORT/MERGE METHODS
  // ==========================================================================

  Future<void> importFavorites(List<Map<String, dynamic>> favorites) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || favorites.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final fav in favorites) {
        final filename = fav['filename'] as String?;
        final addedAt = (fav['added_at'] as num?)?.toDouble();
        if (filename == null || addedAt == null) continue;

        final existing = await txn.query(
          'favorite',
          where: 'filename = ?',
          whereArgs: [filename],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingAddedAt =
              (existing.first['added_at'] as num?)?.toDouble() ?? 0;
          if (addedAt <= existingAddedAt) continue;
        }
        await txn.insert(
            'favorite',
            {
              'filename': filename,
              'added_at': addedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> importSuggestLess(List<Map<String, dynamic>> suggestless) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || suggestless.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final s in suggestless) {
        final filename = s['filename'] as String?;
        final addedAt = (s['added_at'] as num?)?.toDouble();
        if (filename == null || addedAt == null) continue;

        final existing = await txn.query(
          'suggestless',
          where: 'filename = ?',
          whereArgs: [filename],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingAddedAt =
              (existing.first['added_at'] as num?)?.toDouble() ?? 0;
          if (addedAt <= existingAddedAt) continue;
        }
        await txn.insert(
            'suggestless',
            {
              'filename': filename,
              'added_at': addedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> importHidden(List<Map<String, dynamic>> hidden) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || hidden.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final h in hidden) {
        final filename = h['filename'] as String?;
        final hiddenAt = (h['hidden_at'] as num?)?.toDouble();
        if (filename == null || hiddenAt == null) continue;

        final existing = await txn.query(
          'hidden',
          where: 'filename = ?',
          whereArgs: [filename],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingHiddenAt =
              (existing.first['hidden_at'] as num?)?.toDouble() ?? 0;
          if (hiddenAt <= existingHiddenAt) continue;
        }
        await txn.insert(
            'hidden',
            {
              'filename': filename,
              'hidden_at': hiddenAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> importPlaylists(List<Map<String, dynamic>> playlists) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || playlists.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final pl in playlists) {
        final id = pl['id'] as String?;
        final name = pl['name'] as String?;
        final updatedAt = (pl['updated_at'] as num?)?.toDouble();
        if (id == null || name == null) continue;

        final existing = await txn.query(
          'playlist',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingUpdated =
              (existing.first['updated_at'] as num?)?.toDouble() ?? 0;
          if (updatedAt != null && updatedAt <= existingUpdated) {
            // Remote is older or same; only merge songs
            await _mergePlaylistSongs(txn, id, pl['songs'] as List?);
            continue;
          }
        }

        await txn.insert(
            'playlist',
            {
              'id': id,
              'name': name,
              'description': pl['description'],
              'is_recommendation': pl['is_recommendation'] ?? 0,
              'created_at': pl['created_at'] ?? updatedAt ?? 0,
              'updated_at': updatedAt ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);

        await txn
            .delete('playlist_song', where: 'playlist_id = ?', whereArgs: [id]);
        await _mergePlaylistSongs(txn, id, pl['songs'] as List?);
      }
    });
  }

  Future<void> _mergePlaylistSongs(
      Transaction txn, String playlistId, List? songs) async {
    if (songs == null) return;
    for (final s in songs) {
      final sm = s as Map<String, dynamic>;
      final filename = sm['song_filename'] as String?;
      if (filename == null) continue;
      await txn.insert(
          'playlist_song',
          {
            'playlist_id': playlistId,
            'song_filename': filename,
            'added_at': sm['added_at'] ??
                DateTime.now().millisecondsSinceEpoch / 1000.0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> importMergedGroups(List<Map<String, dynamic>> groups) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || groups.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final g in groups) {
        final id = g['id'] as String?;
        if (id == null) continue;

        final existing = await txn.query(
          'merged_song_group',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert(
              'merged_song_group',
              {
                'id': id,
                'priority_filename': g['priority_filename'],
                'created_at': g['created_at'] ??
                    DateTime.now().millisecondsSinceEpoch / 1000.0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);

          final songs = g['songs'] as List?;
          if (songs != null) {
            for (final s in songs) {
              final sm = s as Map<String, dynamic>;
              await txn.insert(
                  'merged_song',
                  {
                    'filename': sm['filename'],
                    'group_id': id,
                    'added_at': sm['added_at'] ??
                        DateTime.now().millisecondsSinceEpoch / 1000.0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      }
    });
  }

  Future<void> importArtistArtBatch(
      List<Map<String, dynamic>> artistArt) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || artistArt.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final a in artistArt) {
        final name = a['artist_name'] as String?;
        if (name == null) continue;

        final updatedAt = (a['updated_at'] as num?)?.toDouble() ?? 0;
        final existing = await txn.query(
          'artist_art',
          where: 'artist_name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingUpdated =
              (existing.first['updated_at'] as num?)?.toDouble() ?? 0;
          if (updatedAt <= existingUpdated) continue;
        }

        await txn.insert('artist_art', a,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> importAlbumArtBatch(List<Map<String, dynamic>> albumArt) async {
    await _ensureInitialized();
    if (_userDataDatabase == null || albumArt.isEmpty) return;
    await _userDataDatabase!.transaction((txn) async {
      for (final a in albumArt) {
        final key = a['album_key'] as String?;
        if (key == null) continue;

        final updatedAt = (a['updated_at'] as num?)?.toDouble() ?? 0;
        final existing = await txn.query(
          'album_art',
          where: 'album_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final existingUpdated =
              (existing.first['updated_at'] as num?)?.toDouble() ?? 0;
          if (updatedAt <= existingUpdated) continue;
        }

        await txn.insert('album_art', a,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String?> getTranslatedLyrics(
      String filename, String targetLang) async {
    await _ensureInitialized();
    final results = await _userDataDatabase!.query(
      'translated_lyrics',
      columns: ['translated_content'],
      where: 'filename = ? AND target_lang = ?',
      whereArgs: [filename, targetLang.toLowerCase()],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['translated_content'] as String?;
  }

  Future<void> saveTranslatedLyrics(
    String filename,
    String targetLang,
    String content,
  ) async {
    await _ensureInitialized();
    await _userDataDatabase!.insert(
      'translated_lyrics',
      {
        'filename': filename,
        'target_lang': targetLang.toLowerCase(),
        'translated_content': content,
        'updated_at': DateTime.now().millisecondsSinceEpoch / 1000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTranslatedLyrics(String filename,
      [String? targetLang]) async {
    await _ensureInitialized();
    if (targetLang != null) {
      await _userDataDatabase!.delete(
        'translated_lyrics',
        where: 'filename = ? AND target_lang = ?',
        whereArgs: [filename, targetLang.toLowerCase()],
      );
    } else {
      await _userDataDatabase!.delete(
        'translated_lyrics',
        where: 'filename = ?',
        whereArgs: [filename],
      );
    }
  }

  Future<void> close() async {
    await _statsDatabase?.close();
    await _userDataDatabase?.close();
    _statsDatabase = null;
    _userDataDatabase = null;
    _initCompleter = null;
  }
}

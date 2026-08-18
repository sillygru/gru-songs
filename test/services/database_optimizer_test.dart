import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wispie/services/database_optimizer_service.dart';
import '../test_helpers.dart';

/// Opens a fresh in-memory database with tables for testing optimization rules.
Future<Database> _openFullDb() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
  );
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
    CREATE TABLE IF NOT EXISTS favorite (
      filename TEXT PRIMARY KEY,
      added_at REAL
    )
  ''');
  return db;
}

void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  final optimizer = DatabaseOptimizerService();

  // ---------------------------------------------------------------------------
  // Orphan cleanup
  // ---------------------------------------------------------------------------

  group('_fixOrphanedRecords', () {
    test('removes orphaned playlist_song rows', () async {
      final db = await _openFullDb();

      await db.insert('playlist_song', {
        'playlist_id': 'nonexistent-playlist',
        'song_filename': 'song.mp3',
        'added_at': 1000.0,
      });

      final result = await optimizer.fixOrphanedRecordsForTest(db);

      expect(result['issuesFound'], greaterThan(0));
      expect(result['issuesFixed'], greaterThan(0));

      final remaining = await db.query('playlist_song',
          where: 'playlist_id = ?', whereArgs: ['nonexistent-playlist']);
      expect(remaining, isEmpty);

      await db.close();
    });

    test('removes orphaned merged_song rows', () async {
      final db = await _openFullDb();

      await db.insert('merged_song', {
        'filename': 'orphan.mp3',
        'group_id': 'nonexistent-group',
        'added_at': 1000.0,
      });

      final result = await optimizer.fixOrphanedRecordsForTest(db);

      expect(result['issuesFound'], greaterThan(0));
      expect(result['issuesFixed'], greaterThan(0));

      final remaining = await db.query('merged_song',
          where: 'filename = ?', whereArgs: ['orphan.mp3']);
      expect(remaining, isEmpty);

      await db.close();
    });

    test('does not remove valid records', () async {
      final db = await _openFullDb();

      await db.insert('playlist', {
        'id': 'p1',
        'name': 'My List',
        'created_at': 1000.0,
        'updated_at': 1000.0
      });
      await db.insert('playlist_song', {
        'playlist_id': 'p1',
        'song_filename': 'valid.mp3',
        'added_at': 1000.0,
      });

      final result = await optimizer.fixOrphanedRecordsForTest(db);

      expect(result['issuesFixed'], 0);

      final remaining = await db
          .query('playlist_song', where: 'playlist_id = ?', whereArgs: ['p1']);
      expect(remaining, isNotEmpty);

      await db.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Duplicate cleanup
  // ---------------------------------------------------------------------------

  group('_fixDuplicateRecords', () {
    test('removes duplicate favorite entries keeping most recent', () async {
      final db = await _openFullDb();

      // Insert two rows with same filename - bypass PK by using raw SQL with
      // a temp table to simulate legacy data with relaxed constraints.
      // Instead, recreate favorite without PK constraint to simulate old data.
      await db.execute('DROP TABLE IF EXISTS favorite');
      await db.execute('CREATE TABLE favorite (filename TEXT, added_at REAL)');
      await db.insert('favorite', {'filename': 'song.mp3', 'added_at': 1000.0});
      await db.insert('favorite', {'filename': 'song.mp3', 'added_at': 2000.0});

      final result = await optimizer.fixDuplicateRecordsForTest(db);

      expect(result['issuesFound'], 1);
      expect(result['issuesFixed'], 1);

      final remaining = await db.query('favorite');
      expect(remaining.length, 1);
      expect(remaining.first['added_at'], 2000.0,
          reason: 'Should keep the most recent');

      await db.close();
    });

    test('does not modify tables without duplicates', () async {
      final db = await _openFullDb();

      await db
          .insert('favorite', {'filename': 'unique.mp3', 'added_at': 1000.0});

      final result = await optimizer.fixDuplicateRecordsForTest(db);

      expect(result['issuesFixed'], 0);

      final remaining = await db.query('favorite');
      expect(remaining.length, 1);

      await db.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Short session and play event cleanup
  // ---------------------------------------------------------------------------

  group('_deleteShortSessions', () {
    Future<Database> openStatsDb() async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
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
          background_duration REAL
        )
      ''');
      return db;
    }

    test('deletes sessions shorter than 60 seconds and their play events',
        () async {
      final db = await openStatsDb();

      // Session 1: 30s long (< 60s) -> should be deleted
      await db.insert('playsession', {
        'id': 'short_sess_1',
        'start_time': 1000.0,
        'end_time': 1030.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'short_sess_1',
        'song_filename': 'short_song.mp3',
        'timestamp': 1000.0,
        'duration_played': 30.0,
        'total_length': 200.0,
      });

      // Session 2: 0s duration (< 60s) -> should be deleted
      await db.insert('playsession', {
        'id': 'zero_sess_2',
        'start_time': 2000.0,
        'end_time': 2000.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'zero_sess_2',
        'song_filename': 'skipped_song.mp3',
        'timestamp': 2000.0,
        'duration_played': 0.0,
        'total_length': 180.0,
      });

      // Session 3: 59.9s duration (< 60s) -> should be deleted
      await db.insert('playsession', {
        'id': 'almost_60s_sess',
        'start_time': 3000.0,
        'end_time': 3059.9,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'almost_60s_sess',
        'song_filename': 'almost_song.mp3',
        'timestamp': 3000.0,
        'duration_played': 59.9,
        'total_length': 300.0,
      });

      // Session 4: Exactly 60.0s (>= 60s) -> should be KEPT
      await db.insert('playsession', {
        'id': 'exact_60s_sess',
        'start_time': 4000.0,
        'end_time': 4060.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'exact_60s_sess',
        'song_filename': 'kept_song_1.mp3',
        'timestamp': 4000.0,
        'duration_played': 60.0,
        'total_length': 180.0,
      });

      // Session 5: 300s duration (>= 60s) -> should be KEPT
      await db.insert('playsession', {
        'id': 'long_sess_5',
        'start_time': 5000.0,
        'end_time': 5300.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'long_sess_5',
        'song_filename': 'kept_song_2.mp3',
        'timestamp': 5000.0,
        'duration_played': 180.0,
        'total_length': 180.0,
      });
      await db.insert('playevent', {
        'session_id': 'long_sess_5',
        'song_filename': 'kept_song_3.mp3',
        'timestamp': 5180.0,
        'duration_played': 120.0,
        'total_length': 200.0,
      });

      final result = await optimizer.deleteShortSessionsForTest(db);

      expect(result['deletedSessions'], 3);
      expect(result['deletedEvents'], 3);

      final remainingSessions = await db.query('playsession', orderBy: 'id ASC');
      expect(remainingSessions.length, 2);
      expect(remainingSessions.map((s) => s['id']),
          containsAll(['exact_60s_sess', 'long_sess_5']));

      final remainingEvents = await db.query('playevent', orderBy: 'id ASC');
      expect(remainingEvents.length, 3);
      expect(
          remainingEvents.map((e) => e['song_filename']),
          containsAll(
              ['kept_song_1.mp3', 'kept_song_2.mp3', 'kept_song_3.mp3']));

      await db.close();
    });

    test('deletes sessions with null timestamps and orphaned play events',
        () async {
      final db = await openStatsDb();

      // Session with NULL end_time
      await db.insert('playsession', {
        'id': 'null_end_sess',
        'start_time': 1000.0,
        'end_time': null,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'null_end_sess',
        'song_filename': 'null_end_song.mp3',
        'timestamp': 1000.0,
        'duration_played': 10.0,
      });

      // Session with NULL start_time
      await db.insert('playsession', {
        'id': 'null_start_sess',
        'start_time': null,
        'end_time': 2000.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'null_start_sess',
        'song_filename': 'null_start_song.mp3',
        'timestamp': 2000.0,
        'duration_played': 10.0,
      });

      // Orphaned play event (session does not exist)
      await db.insert('playevent', {
        'session_id': 'non_existent_session',
        'song_filename': 'orphan_event.mp3',
        'timestamp': 3000.0,
        'duration_played': 50.0,
      });

      // Orphaned play event (session_id is null)
      await db.insert('playevent', {
        'session_id': null,
        'song_filename': 'null_session_event.mp3',
        'timestamp': 3500.0,
        'duration_played': 40.0,
      });

      // Valid session to keep
      await db.insert('playsession', {
        'id': 'valid_sess',
        'start_time': 5000.0,
        'end_time': 5100.0,
        'platform': 'linux',
      });
      await db.insert('playevent', {
        'session_id': 'valid_sess',
        'song_filename': 'valid_song.mp3',
        'timestamp': 5000.0,
        'duration_played': 100.0,
      });

      final result = await optimizer.deleteShortSessionsForTest(db);

      expect(result['deletedSessions'], 2);
      expect(result['deletedEvents'], 4); // 2 from null sessions + 2 orphans

      final remainingSessions = await db.query('playsession');
      expect(remainingSessions.length, 1);
      expect(remainingSessions.first['id'], 'valid_sess');

      final remainingEvents = await db.query('playevent');
      expect(remainingEvents.length, 1);
      expect(remainingEvents.first['song_filename'], 'valid_song.mp3');

      await db.close();
    });
  });
}


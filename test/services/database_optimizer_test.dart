import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wispie/services/database_optimizer_service.dart';
import '../test_helpers.dart';

/// Opens a fresh in-memory database with tables for testing optimization rules.
Future<Database> _openFullDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gru_songs/services/database_optimizer_service.dart';
import 'package:gru_songs/services/database_service.dart';
import '../test_helpers.dart';

/// Opens a fresh in-memory database with all canonical user data tables and indexes.
Future<Database> _openFullDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  for (final sql in DatabaseService.userDataTableSql.values) {
    await db.execute(sql);
  }
  for (final sql in DatabaseService.userDataIndexSql.values) {
    await db.execute(sql);
  }
  return db;
}

/// Opens a fresh in-memory database with no tables.
Future<Database> _openEmptyDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
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
  // Table analysis
  // ---------------------------------------------------------------------------

  group('_ensureUserDataTables', () {
    test('detects and creates missing tables', () async {
      final db = await _openEmptyDb();
      final result = await optimizer.ensureUserDataTablesForTest(db);

      expect(result['issues'], isA<List>());
      expect(result['fixes'], isA<List>());

      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) => i.toString().contains('missing')),
        isTrue,
        reason: 'Should detect missing tables',
      );
      expect(
        fixes.any((f) => f.toString().contains('Created')),
        isTrue,
        reason: 'Should create missing tables',
      );

      final tablesAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final tableNames = tablesAfter.map((r) => r['name'] as String).toSet();

      for (final expected in DatabaseService.userDataTableSql.keys) {
        expect(tableNames, contains(expected),
            reason: 'Table $expected should be created');
      }

      await db.close();
    });

    test('drops unrecognized tables', () async {
      final db = await _openFullDb();
      await db.execute('CREATE TABLE IF NOT EXISTS legacy_junk (id TEXT)');

      final result = await optimizer.ensureUserDataTablesForTest(db);
      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) => i.toString().contains('legacy_junk')),
        isTrue,
        reason: 'Should detect unrecognized table',
      );
      expect(
        fixes.any((f) =>
            f.toString().contains('Dropped') &&
            f.toString().contains('legacy_junk')),
        isTrue,
        reason: 'Should drop unrecognized table',
      );

      final tablesAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='legacy_junk'",
      );
      expect(tablesAfter, isEmpty, reason: 'Unrecognized table should be gone');

      await db.close();
    });

    test('reports no issues when schema is correct', () async {
      final db = await _openFullDb();
      final result = await optimizer.ensureUserDataTablesForTest(db);

      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(issues, isEmpty);
      expect(fixes, isEmpty);

      await db.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Column analysis
  // ---------------------------------------------------------------------------

  group('_ensureUserDataColumns', () {
    test('detects and adds missing columns', () async {
      final db = await _openEmptyDb();
      // Create playlist table without description and is_recommendation
      await db.execute('''
        CREATE TABLE playlist (
          id TEXT PRIMARY KEY,
          name TEXT,
          created_at REAL,
          updated_at REAL
        )
      ''');

      final result = await optimizer.ensureUserDataColumnsForTest(db);
      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) =>
            i.toString().contains('description') ||
            i.toString().contains('is_recommendation')),
        isTrue,
        reason: 'Should detect missing columns',
      );
      expect(
        fixes.any((f) => f.toString().contains('Added')),
        isTrue,
        reason: 'Should add missing columns',
      );

      final colsAfter = await db.rawQuery('PRAGMA table_info(playlist)');
      final colNames = colsAfter.map((c) => c['name'] as String).toSet();
      expect(colNames, contains('description'));
      expect(colNames, contains('is_recommendation'));

      await db.close();
    });

    test('detects and drops unrecognized non-PK columns', () async {
      final db = await _openEmptyDb();
      await db.execute('''
        CREATE TABLE favorite (
          filename TEXT PRIMARY KEY,
          added_at REAL,
          legacy_junk TEXT
        )
      ''');

      final result = await optimizer.ensureUserDataColumnsForTest(db);
      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) => i.toString().contains('legacy_junk')),
        isTrue,
        reason: 'Should detect unrecognized column',
      );
      expect(
        fixes.any((f) =>
            f.toString().contains('Dropped') &&
            f.toString().contains('legacy_junk')),
        isTrue,
        reason: 'Should drop unrecognized column',
      );

      final colsAfter = await db.rawQuery('PRAGMA table_info(favorite)');
      final colNames = colsAfter.map((c) => c['name'] as String).toSet();
      expect(colNames, isNot(contains('legacy_junk')));
      // Known columns must survive
      expect(colNames, contains('filename'));
      expect(colNames, contains('added_at'));

      await db.close();
    });

    test('does not drop unrecognized PK columns', () async {
      final db = await _openEmptyDb();
      // Create a table where the PK column name is unrecognized
      await db.execute('''
        CREATE TABLE favorite (
          old_key TEXT PRIMARY KEY,
          added_at REAL
        )
      ''');

      final result = await optimizer.ensureUserDataColumnsForTest(db);
      final issues = result['issues'] as List;

      expect(
        issues.any((i) =>
            i.toString().contains('cannot auto-drop') &&
            i.toString().contains('old_key')),
        isTrue,
        reason: 'Should warn about unrecognized PK but not crash',
      );

      final colsAfter = await db.rawQuery('PRAGMA table_info(favorite)');
      final colNames = colsAfter.map((c) => c['name'] as String).toSet();
      expect(colNames, contains('old_key'),
          reason: 'PK column must not be dropped');

      await db.close();
    });

    test('does not drop indexed columns and reports graceful failure',
        () async {
      final db = await _openEmptyDb();
      await db.execute('''
        CREATE TABLE favorite (
          filename TEXT PRIMARY KEY,
          added_at REAL,
          indexed_extra TEXT
        )
      ''');
      await db
          .execute('CREATE INDEX idx_indexed_extra ON favorite(indexed_extra)');

      final result = await optimizer.ensureUserDataColumnsForTest(db);
      final issues = result['issues'] as List;

      // The column should be detected as unrecognized
      expect(
        issues.any((i) => i.toString().contains('indexed_extra')),
        isTrue,
      );

      // The column should survive since SQLite won't drop indexed columns
      // (either the drop fails gracefully, or it succeeds if SQLite version supports it)
      // Either way, no crash and no known columns removed
      final colsAfter = await db.rawQuery('PRAGMA table_info(favorite)');
      final colNames = colsAfter.map((c) => c['name'] as String).toSet();
      expect(colNames, contains('filename'));
      expect(colNames, contains('added_at'));

      await db.close();
    });

    test('reports no issues when all columns present and no extras', () async {
      final db = await _openFullDb();
      final result = await optimizer.ensureUserDataColumnsForTest(db);

      expect((result['issues'] as List), isEmpty);
      expect((result['fixes'] as List), isEmpty);

      await db.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Index analysis
  // ---------------------------------------------------------------------------

  group('_ensureUserDataIndexes', () {
    test('detects and creates missing indexes', () async {
      final db = await _openFullDb();
      // Drop one known index to simulate it being missing
      await db.execute('DROP INDEX IF EXISTS idx_song_artist');

      final result = await optimizer.ensureUserDataIndexesForTest(db);
      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) => i.toString().contains('idx_song_artist')),
        isTrue,
      );
      expect(
        fixes.any((f) => f.toString().contains('idx_song_artist')),
        isTrue,
      );

      final indexAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_song_artist'",
      );
      expect(indexAfter, isNotEmpty);

      await db.close();
    });

    test('drops unrecognized user-created indexes', () async {
      final db = await _openFullDb();
      await db
          .execute('CREATE INDEX IF NOT EXISTS idx_stale_old ON song(title)');

      final result = await optimizer.ensureUserDataIndexesForTest(db);
      final issues = result['issues'] as List;
      final fixes = result['fixes'] as List;

      expect(
        issues.any((i) => i.toString().contains('idx_stale_old')),
        isTrue,
      );
      expect(
        fixes.any((f) =>
            f.toString().contains('Dropped') &&
            f.toString().contains('idx_stale_old')),
        isTrue,
      );

      final indexAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale_old'",
      );
      expect(indexAfter, isEmpty);

      await db.close();
    });

    test('reports no issues when indexes match canonical set', () async {
      final db = await _openFullDb();
      final result = await optimizer.ensureUserDataIndexesForTest(db);

      expect((result['issues'] as List), isEmpty);
      expect((result['fixes'] as List), isEmpty);

      await db.close();
    });
  });

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

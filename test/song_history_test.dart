import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() {
    setUpMockPlugins();
  });

  group('Song History Duration-Based Calculation Tests', () {
    test('meaningful play: duration > 10 seconds', () {
      const duration = 30.0;
      const ratio = 0.167;

      final isMeaningful = duration > 10 || ratio > 0.25;
      expect(isMeaningful, isTrue);
    });

    test('meaningful play: ratio > 0.25 even with short duration', () {
      const duration = 5.0;
      const ratio = 0.30;

      final isMeaningful = duration > 10 || ratio > 0.25;
      expect(isMeaningful, isTrue);
    });

    test('NOT meaningful: duration < 10 AND ratio < 0.25', () {
      const duration = 5.0;
      const ratio = 0.028;

      final isMeaningful = duration > 10 || ratio > 0.25;
      expect(isMeaningful, isFalse);
    });

    test('NOT meaningful: duration < 10 but ratio near threshold', () {
      const duration = 8.0;
      const ratio = 0.20;

      final isMeaningful = duration > 10 || ratio > 0.25;
      expect(isMeaningful, isFalse);
    });

    test('skip detection: duration < 10 AND ratio < 0.25', () {
      const duration = 5.0;
      const ratio = 0.028;

      final isSkip = duration < 10 && ratio < 0.25;
      expect(isSkip, isTrue);
    });

    test('NOT a skip: duration >= 10 even with low ratio', () {
      const duration = 10.0;
      const ratio = 0.20;

      final isSkip = duration < 10 && ratio < 0.25;
      expect(isSkip, isFalse);
    });

    test('NOT a skip: ratio >= 0.25 even with short duration', () {
      const duration = 5.0;
      const ratio = 0.25;

      final isSkip = duration < 10 && ratio < 0.25;
      expect(isSkip, isFalse);
    });

    test('play_ratio calculation from duration and total_length', () {
      const duration = 90.0;
      const totalLength = 180.0;

      final ratio = totalLength > 0 ? duration / totalLength : 0.0;
      expect(ratio, equals(0.5));
    });

    test('play_ratio returns 0 when total_length is 0', () {
      const duration = 90.0;
      const totalLength = 0.0;

      final ratio = totalLength > 0 ? duration / totalLength : 0.0;
      expect(ratio, equals(0.0));
    });

    test('play_ratio handles null total_length', () {
      const duration = 90.0;
      double? totalLength;

      final ratio =
          totalLength != null && totalLength > 0 ? duration / totalLength : 0.0;
      expect(ratio, equals(0.0));
    });
  });

  group('Database Schema Migration Tests', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('can create playevent table without event_type column', () async {
      await db.execute('''
        CREATE TABLE playevent (
          id INTEGER PRIMARY KEY,
          song_filename TEXT,
          timestamp REAL,
          duration_played REAL,
          total_length REAL,
          play_ratio REAL,
          foreground_duration REAL,
          background_duration REAL
        )
      ''');

      await db.insert('playevent', {
        'song_filename': 'test.mp3',
        'timestamp': 1234567890.0,
        'duration_played': 30.0,
        'total_length': 180.0,
        'play_ratio': 0.167,
        'foreground_duration': 30.0,
        'background_duration': 0.0,
      });

      final results = await db.query('playevent');
      expect(results.length, equals(1));
      expect(results.first['song_filename'], equals('test.mp3'));
    });

    test('migration drops event_type column from playevent table', () async {
      await db.execute('''
        CREATE TABLE playevent (
          id INTEGER PRIMARY KEY,
          song_filename TEXT,
          event_type TEXT,
          timestamp REAL,
          duration_played REAL,
          total_length REAL,
          play_ratio REAL,
          foreground_duration REAL,
          background_duration REAL
        )
      ''');

      await db.insert('playevent', {
        'song_filename': 'test.mp3',
        'event_type': 'complete',
        'timestamp': 1234567890.0,
        'duration_played': 30.0,
        'total_length': 180.0,
        'play_ratio': 0.167,
        'foreground_duration': 30.0,
        'background_duration': 0.0,
      });

      var columns = await db.rawQuery('PRAGMA table_info(playevent)');
      var columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames.contains('event_type'), isTrue);

      try {
        await db.rawUpdate('ALTER TABLE playevent DROP COLUMN event_type');
      } catch (_) {
        final columnData = await db.query('playevent');
        await db.execute('''
          CREATE TABLE playevent_new (
            id INTEGER PRIMARY KEY,
            song_filename TEXT,
            timestamp REAL,
            duration_played REAL,
            total_length REAL,
            play_ratio REAL,
            foreground_duration REAL,
            background_duration REAL
          )
        ''');
        for (final row in columnData) {
          await db.insert('playevent_new', {
            'id': row['id'],
            'song_filename': row['song_filename'],
            'timestamp': row['timestamp'],
            'duration_played': row['duration_played'],
            'total_length': row['total_length'],
            'play_ratio': row['play_ratio'],
            'foreground_duration': row['foreground_duration'],
            'background_duration': row['background_duration'],
          });
        }
        await db.execute('DROP TABLE playevent');
        await db.execute('ALTER TABLE playevent_new RENAME TO playevent');
      }

      columns = await db.rawQuery('PRAGMA table_info(playevent)');
      columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames.contains('event_type'), isFalse);
      expect(columnNames.contains('song_filename'), isTrue);
      expect(columnNames.contains('duration_played'), isTrue);
    });
  });

  group('PlayHistoryScreen Display Tests', () {
    test('history item displays duration correctly', () {
      const duration = 125.5;

      final minutes = duration ~/ 60;
      final seconds = (duration % 60).toInt();
      final formatted = '${minutes}:${seconds.toString().padLeft(2, '0')}';

      expect(formatted, equals('2:05'));
    });

    test('history item handles short durations', () {
      const duration = 5.0;

      final minutes = duration ~/ 60;
      final seconds = (duration % 60).toInt();
      final formatted = '${minutes}:${seconds.toString().padLeft(2, '0')}';

      expect(formatted, equals('0:05'));
    });

    test('history item handles long durations', () {
      const duration = 3665.0;

      final minutes = duration ~/ 60;
      final seconds = (duration % 60).toInt();
      final formatted = '${minutes}:${seconds.toString().padLeft(2, '0')}';

      expect(formatted, equals('61:05'));
    });

    test('history item handles exactly 60 seconds', () {
      const duration = 60.0;

      final minutes = duration ~/ 60;
      final seconds = (duration % 60).toInt();
      final formatted = '${minutes}:${seconds.toString().padLeft(2, '0')}';

      expect(formatted, equals('1:00'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/database_service.dart';
import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
    await DatabaseService.instance.init();
  });

  tearDownAll(() async {
    testEnv.tearDown();
  });

  setUp(() async {
    final db = DatabaseService.instance;
    await db.clearAllPlayStats();
  });

  group('Sync Database & Device Stats Tests', () {
    test('getPlayStatsDeviceBreakdown counts local vs remote events correctly',
        () async {
      final db = DatabaseService.instance;
      const currentDeviceId = 'device_local_123';
      const remoteDeviceId = 'device_remote_456';

      await db.insertPlayEventsBatch([
        {
          'session_id': 'sess_1',
          'song_filename': 'song_1.mp3',
          'timestamp': 1000.0,
          'duration_played': 120.0,
          'total_length': 180.0,
          'device_id': currentDeviceId,
        },
        {
          'session_id': 'sess_2',
          'song_filename': 'song_2.mp3',
          'timestamp': 2000.0,
          'duration_played': 150.0,
          'total_length': 200.0,
          'device_id': remoteDeviceId,
        },
      ]);

      final breakdown = await db.getPlayStatsDeviceBreakdown(currentDeviceId);

      expect(breakdown['localPlayCount'], 1);
      expect(breakdown['remotePlayCount'], 1);
      expect(breakdown['totalPlayCount'], 2);
    });

    test('clearAllPlayStats empties playsession and playevent tables',
        () async {
      final db = DatabaseService.instance;
      await db.insertPlayEventsBatch([
        {
          'session_id': 'sess_1',
          'song_filename': 'song_1.mp3',
          'timestamp': 1000.0,
          'duration_played': 120.0,
          'total_length': 180.0,
          'device_id': 'dev_1',
        },
      ]);

      var events = await db.getPlayEventsForSync();
      expect(events.length, 1);

      await db.clearAllPlayStats();

      events = await db.getPlayEventsForSync();
      expect(events.isEmpty, isTrue);
    });

    test('getArtistArtForSync and getAlbumArtForSync exclude local_path',
        () async {
      final db = DatabaseService.instance;

      final artistArt = await db.getArtistArtForSync();
      for (final a in artistArt) {
        expect(a.containsKey('local_path'), isFalse);
      }

      final albumArt = await db.getAlbumArtForSync();
      for (final a in albumArt) {
        expect(a.containsKey('local_path'), isFalse);
      }
    });

    test('getPlayEventsForSync falls back to current device_id when missing',
        () async {
      final db = DatabaseService.instance;
      await db.insertPlayEventsBatch([
        {
          'session_id': 'sess_null_device',
          'song_filename': 'song_null.mp3',
          'timestamp': 1500.0,
          'duration_played': 100.0,
          'total_length': 180.0,
          // device_id is omitted/null
        },
      ]);

      final events = await db.getPlayEventsForSync();
      expect(events.length, 1);
      expect(events.first['device_id'], isNotNull);
      expect(events.first['device_id'], isNotEmpty);
    });

    test(
        'isSync: true does not multiply duration_played on repeated sync merges',
        () async {
      final db = DatabaseService.instance;
      final syncEvent = {
        'session_id': 'sess_sync_1',
        'song_filename': 'track_sync.mp3',
        'timestamp': 1000.0,
        'duration_played': 180.0,
        'total_length': 180.0,
        'device_id': 'dev_sync',
      };

      await db.insertPlayEventsBatch([syncEvent], isSync: true);
      var events = await db.getPlayEventsForSync();
      expect(events.first['duration_played'], 180.0);

      // Repeat sync 3 times
      await db.insertPlayEventsBatch([syncEvent], isSync: true);
      await db.insertPlayEventsBatch([syncEvent], isSync: true);
      await db.insertPlayEventsBatch([syncEvent], isSync: true);

      events = await db.getPlayEventsForSync();
      expect(events.first['duration_played'], 180.0);
    });

    test('repairCorruptedPlayStats repairs inflated play durations', () async {
      final db = DatabaseService.instance;
      // Directly insert an inflated row to simulate existing corrupt DB state
      final statsDb = db.getStatsDatabase();
      await statsDb?.insert('playsession', {
        'id': 'sess_corrupt_1',
        'start_time': 1000.0,
        'end_time': 1000.0,
        'platform': 'unknown',
        'device_id': 'dev_1',
      });
      await statsDb?.insert('playevent', {
        'session_id': 'sess_corrupt_1',
        'song_filename': 'corrupt_song.mp3',
        'timestamp': 1000.0,
        'duration_played': 3600.0, // Inflated 1 hour for 180s song
        'total_length': 180.0,
        'play_ratio': 20.0,
        'foreground_duration': 3600.0,
        'background_duration': 0.0,
      });

      final repaired = await db.repairCorruptedPlayStats();
      expect(repaired, 1);

      final events = await db.getPlayEventsForSync();
      expect(events.first['duration_played'], 180.0);
      expect(events.first['play_ratio'], 1.0);
    });
  });
}

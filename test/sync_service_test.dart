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
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/stats_service.dart';
import 'package:wispie/services/database_service.dart';
import 'test_helpers.dart';

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService() : super.forTest();

  bool failBatchWrites = false;
  final List<Map<String, dynamic>> insertedSingles = [];
  final List<Map<String, dynamic>> insertedBatchEvents = [];

  @override
  Future<bool> init() async => false;

  @override
  Future<void> insertPlayEvent(Map<String, dynamic> event,
      {bool isSync = false}) async {
    insertedSingles.add(Map<String, dynamic>.from(event));
  }

  @override
  Future<void> insertPlayEventsBatch(List<Map<String, dynamic>> events,
      {bool isSync = false}) async {
    if (failBatchWrites) {
      throw Exception('batch write failed');
    }
    insertedBatchEvents
        .addAll(events.map((event) => Map<String, dynamic>.from(event)));
  }
}

void main() {
  late TestEnvironment testEnv;
  late DatabaseService originalDatabaseService;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
    originalDatabaseService = DatabaseService.instance;
  });

  tearDownAll(() {
    DatabaseService.instance = originalDatabaseService;
    testEnv.tearDown();
  });

  group('Stats Service Basic Tests', () {
    test('play history derives listen/skip from play ratio', () async {
      final testDb = DatabaseService.forTest();
      final previousDb = DatabaseService.instance;
      DatabaseService.instance = testDb;

      try {
        await testDb.init();

        await testDb.insertPlayEvent({
          'session_id': 'session_listen',
          'song_filename': 'listen.mp3',
          'timestamp': 1.0,
          'duration_played': 120.0,
          'total_length': 180.0,
          'foreground_duration': 120.0,
          'background_duration': 0.0,
        });

        await testDb.insertPlayEvent({
          'session_id': 'session_skip',
          'song_filename': 'skip.mp3',
          'timestamp': 2.0,
          'duration_played': 5.0,
          'total_length': 180.0,
          'foreground_duration': 5.0,
          'background_duration': 0.0,
        });

        final history = await testDb.getPlayHistory(limit: 10);
        final listenEvent =
            history.firstWhere((e) => e.filename == 'listen.mp3');
        final skipEvent = history.firstWhere((e) => e.filename == 'skip.mp3');

        expect(listenEvent.eventType, 'listen');
        expect(skipEvent.eventType, 'skip');
      } finally {
        await testDb.close();
        DatabaseService.instance = previousDb;
      }
    });

    test('flush keeps buffered stats when batch insert fails', () async {
      final fakeDb = _FakeDatabaseService()..failBatchWrites = true;
      DatabaseService.instance = fakeDb;
      final statsService = StatsService();

      statsService.setBackground(true);
      await statsService.trackStats({
        'song_filename': 'test.mp3',
        'duration_played': 30.0,
        'foreground_duration': 30.0,
        'background_duration': 0.0,
        'total_length': 180.0,
      });

      await statsService.flush();
      expect(fakeDb.insertedBatchEvents, isEmpty);

      fakeDb.failBatchWrites = false;
      await statsService.flush();

      expect(fakeDb.insertedBatchEvents, hasLength(1));
      expect(fakeDb.insertedBatchEvents.first['song_filename'], 'test.mp3');
    });
  });
}

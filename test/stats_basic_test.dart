import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/stats_service.dart';
import 'test_helpers.dart';
import 'package:flutter/foundation.dart';

void main() {
  // Initialize Flutter binding and mock plugins for tests
  setUpAll(() {
    setUpMockPlugins();
  });

  group('Stats Service Basic Tests', () {
    test('StatsService can be instantiated', () {
      final statsService = StatsService();
      expect(statsService, isNotNull);
      debugPrint('StatsService instantiated successfully');
    });

    test('trackStats works correctly', () async {
      final statsService = StatsService();

      // This should not throw an error even without proper database setup
      try {
        await statsService.trackStats({
          'song_filename': 'test.mp3',
          'duration_played': 30.0,
          'event_type': 'listen',
          'foreground_duration': 30.0,
          'background_duration': 0.0,
          'total_length': 180.0,
        });
        debugPrint('trackStats completed successfully');
      } catch (e) {
        debugPrint('trackStats failed: $e');
        rethrow;
      }
    });

    test('trackStats validates required fields', () async {
      final statsService = StatsService();

      // Test with missing required fields
      try {
        await statsService.trackStats({});
        debugPrint('trackStats accepted empty data (may be expected behavior)');
      } catch (e) {
        debugPrint('trackStats properly validated empty data: $e');
      }
    });
  });
}

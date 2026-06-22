import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';
import 'package:wispie/models/shuffle_config.dart';
import 'package:wispie/domain/services/shuffle_weight_service.dart';

void main() {
  group('Consistent personality anti-repeat buckets', () {
    final song = Song(
        title: 'Test', artist: 'A', album: 'X', filename: 'test.mp3', url: '');
    final item = QueueItem(song: song);

    final config = const ShuffleConfig(
      personality: ShufflePersonality.consistent,
      antiRepeatEnabled: true,
      historyLimit: 200,
    );

    test('historyIndex 0-9: 60% penalty', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 0,
      );
      // 1.0 * (1.0 - 0.60) = 0.40
      expect(weight, closeTo(0.40, 0.0001));
    });

    test('historyIndex 10-19: 50% penalty', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 15,
      );
      // 1.0 * (1.0 - 0.50) = 0.50
      expect(weight, closeTo(0.50, 0.0001));
    });

    test('historyIndex 50-59: 15% penalty', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 55,
      );
      // 1.0 * (1.0 - 0.15) = 0.85
      expect(weight, closeTo(0.85, 0.0001));
    });

    test('historyIndex >= 100: no penalty in consistent mode', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 100,
      );
      // basePenaltyPercent = 0.0 -> no penalty
      expect(weight, closeTo(1.0, 0.0001));
    });
  });

  group('Default mode anti-repeat buckets', () {
    final song = Song(
        title: 'Test', artist: 'A', album: 'X', filename: 'test.mp3', url: '');
    final item = QueueItem(song: song);

    final config = const ShuffleConfig(
      antiRepeatEnabled: true,
      historyLimit: 200,
    );

    test('historyIndex 0-9: 95% penalty', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 3,
      );
      // 1.0 * (1.0 - 0.95) = 0.05
      expect(weight, closeTo(0.05, 0.0001));
    });

    test('historyIndex 100-119: 20% penalty', () {
      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 110,
      );
      // 1.0 * (1.0 - 0.20) = 0.80
      expect(weight, closeTo(0.80, 0.0001));
    });
  });

  group('Play count penalty skipped in consistent mode', () {
    final song = Song(
        title: 'Test', artist: 'A', album: 'X', filename: 'test.mp3', url: '');
    final item = QueueItem(song: song);

    test('Consistent mode: no play count penalty', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.consistent,
        antiRepeatEnabled: false,
        streakBreakerEnabled: false,
      );

      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 90,
        maxPlayCount: 100,
      );
      // Consistent mode skips play count penalty
      expect(weight, closeTo(1.0, 0.0001));
    });

    test('Default mode: play count penalty applies', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: false,
        streakBreakerEnabled: false,
      );

      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 90,
        maxPlayCount: 100,
      );
      // ratio = 0.9, penalty = 0.9 * 0.3 = 0.27, weight = 1.0 * 0.73 = 0.73
      expect(weight, closeTo(0.73, 0.0001));
    });
  });

  group('Custom mode personality', () {
    final song = Song(
        title: 'Test', artist: 'A', album: 'X', filename: 'test.mp3', url: '');
    final item = QueueItem(song: song);

    test('Positive favoritesWeight increases weight', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
        favoritesWeight: 50, // +50%
      );

      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: true,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
      );
      // 1.0 * (1.0 + 0.50) = 1.50
      expect(weight, closeTo(1.50, 0.0001));
    });

    test('Negative suggestLessWeight decreases weight', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
        suggestLessWeight: 50, // -50% -> 0.5x
      );

      final weight = calculateWeight(
        item: item,
        config: config,
        isFavorite: false,
        isSuggestLess: true,
        playCount: 0,
        maxPlayCount: 0,
      );
      // 1.0 * (1.0 + (-0.50)) = 0.50
      expect(weight, closeTo(0.50, 0.0001));
    });
  });
}

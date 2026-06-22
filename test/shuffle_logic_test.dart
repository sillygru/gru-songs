import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';
import 'package:wispie/models/shuffle_config.dart';
import 'package:wispie/domain/services/shuffle_weight_service.dart';

void main() {
  group('Shuffle Logic Tests', () {
    final song1 = Song(
        title: 'Test Song 1',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 's1.mp3',
        url: '');

    final songOther = Song(
        title: 'Other',
        artist: 'Other Artist',
        album: 'Other Album',
        filename: 'other.mp3',
        url: '');

    final item1 = QueueItem(song: song1);
    final itemOther = QueueItem(song: songOther);

    test('Anti-repeat penalty reduces weight for recently played songs', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: true,
        historyLimit: 200,
      );

      // historyIndex 0 = most recent -> 95% penalty in non-consistent mode
      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 0,
      );
      // 1.0 * (1.0 - 0.95) = 0.05
      expect(weight, closeTo(0.05, 0.0001));
    });

    test('Anti-repeat penalty is less severe for older history entries', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: true,
        historyLimit: 200,
      );

      // historyIndex 60 -> 50% penalty (non-consistent)
      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 60,
      );
      // 1.0 * (1.0 - 0.50) = 0.50
      expect(weight, closeTo(0.50, 0.0001));
    });

    test('High play ratio (>0.9) increases anti-repeat penalty', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: true,
        historyLimit: 200,
      );

      // historyIndex 10 -> 90% penalty * 1.2 = 108% clamped to 95%
      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 10,
        playRatioInHistory: 0.95,
      );
      // 1.0 * (1.0 - 0.95) = 0.05
      expect(weight, closeTo(0.05, 0.0001));
    });

    test('Custom mode favorite boost increases weight', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
        favoritesWeight: 20, // +20% boost
      );

      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: true,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
      );
      // 1.0 * (1.0 + 20/100) = 1.2
      expect(weight, closeTo(1.2, 0.0001));
    });

    test('Custom mode suggest-less penalty decreases weight', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
        suggestLessWeight: 80, // -80% = 0.2 multiplier
      );

      // suggestLessWeight = 80 -> suggestLessPenalty = -80/100 = -0.8
      // weight *= (1.0 + (-0.8)) = 0.2
      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: true,
        playCount: 0,
        maxPlayCount: 0,
      );
      expect(weight, closeTo(0.2, 0.0001));
    });

    test('Custom mode skip boost: low skip ratio (<0.3) increases weight', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
      );

      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        skipCount: 5,
        skipAvgRatio: 0.1,
      );
      // 1.0 * 1.2 = 1.2
      expect(weight, closeTo(1.2, 0.0001));
    });

    test('Custom mode skip penalty: high skip ratio (>0.7) decreases weight',
        () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.custom,
      );

      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        skipCount: 3,
        skipAvgRatio: 0.9,
      );
      // 1.0 * 0.5 = 0.5
      expect(weight, closeTo(0.5, 0.0001));
    });

    test('Streak breaker penalizes same artist', () {
      final songA = Song(
          title: 'A',
          artist: 'Same Artist',
          album: 'Album X',
          filename: 'a.mp3',
          url: '');
      final songB = Song(
          title: 'B',
          artist: 'Same Artist',
          album: 'Album Y',
          filename: 'b.mp3',
          url: '');
      final itemA = QueueItem(song: songA);
      final itemB = QueueItem(song: songB);

      final config = const ShuffleConfig(
        streakBreakerEnabled: true,
      );

      final weight = calculateWeight(
        item: itemA,
        prev: itemB,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
      );
      // Same artist -> 0.1
      expect(weight, closeTo(0.1, 0.0001));
    });

    test('Lowest weight is clamped to 0.01', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: true,
        streakBreakerEnabled: true,
        historyLimit: 200,
      );

      // historyIndex 0 + same artist should produce very low weight
      final weight = calculateWeight(
        item: item1,
        prev: itemOther,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 0,
        maxPlayCount: 0,
        historyIndex: 0,
      );
      expect(weight, greaterThanOrEqualTo(0.01));
    });

    test('Play count penalty reduces weight for frequently played songs', () {
      final config = const ShuffleConfig(
        antiRepeatEnabled: false,
        streakBreakerEnabled: false,
      );

      // maxPlayCount = 100, playCount = 80 -> ratio = 0.8
      // penalty = 0.8 * 0.3 = 0.24
      // weight = 1.0 * (1.0 - 0.24) = 0.76
      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 80,
        maxPlayCount: 100,
      );
      expect(weight, closeTo(0.76, 0.0001));
    });

    test('No play count penalty in consistent mode', () {
      final config = const ShuffleConfig(
        personality: ShufflePersonality.consistent,
        antiRepeatEnabled: false,
        streakBreakerEnabled: false,
      );

      final weight = calculateWeight(
        item: item1,
        config: config,
        isFavorite: false,
        isSuggestLess: false,
        playCount: 80,
        maxPlayCount: 100,
      );
      // Consistent mode skips the play count penalty -> weight stays 1.0
      expect(weight, closeTo(1.0, 0.0001));
    });
  });
}

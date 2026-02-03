import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';
import 'package:gru_songs/models/shuffle_config.dart';
import 'dart:math';

// Mock/Simplified version of the weight calculation logic from AudioPlayerManager for isolated testing
double calculateWeight(
    QueueItem item,
    QueueItem? prev,
    ShuffleState shuffleState,
    List<String> favorites,
    List<String> suggestLess,
    List<
            ({
              String filename,
              double timestamp,
              double playRatio,
              String eventType
            })>
        playHistory,
    [Map<String, ({int count, double avgRatio})>? skipStats,
    int maxPlayCount = 0]) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;

  // HIERARCHY 1: Global Recency Penalty (Last 200 songs with play ratio weighting)
  if (playHistory.isNotEmpty) {
    int historyIndex = -1;
    double playRatioInHistory = 0.0;

    for (int i = 0; i < playHistory.length; i++) {
      if (playHistory[i].filename == song.filename) {
        historyIndex = i;
        playRatioInHistory = playHistory[i].playRatio;
        break;
      }
    }

    if (historyIndex != -1 && historyIndex < 200) {
      int basePenaltyPercent = 100 - (historyIndex ~/ 2);

      double penaltyMultiplier = 1.0;
      if (playRatioInHistory < 0.25) {
        penaltyMultiplier = 0.3;
      } else if (playRatioInHistory < 0.5) {
        penaltyMultiplier = 0.5;
      } else if (playRatioInHistory < 0.8) {
        penaltyMultiplier = 0.8;
      }

      int adjustedPenaltyPercent =
          (basePenaltyPercent * penaltyMultiplier).round();
      weight *= (1.0 - (adjustedPenaltyPercent / 100.0));
    }
  }

  // HIERARCHY 2: Global Skip Penalty
  if (skipStats != null) {
    final stats = skipStats[song.filename];
    if (stats != null && stats.count >= 3 && stats.avgRatio <= 0.25) {
      double skipPenaltyMultiplier = stats.avgRatio;
      weight *= skipPenaltyMultiplier;
    }
  }

  // HIERARCHY 3: Mode-specific weights
  // 2. Streak Breaker (Same Artist/Album) - only in default mode
  if (config.personality == ShufflePersonality.defaultMode &&
      config.streakBreakerEnabled &&
      prev != null) {
    final prevSong = prev.song;
    if (song.artist != 'Unknown Artist' &&
        prevSong.artist != 'Unknown Artist') {
      if (song.artist == prevSong.artist) {
        weight *= 0.5;
      }
    }
    if (song.album != 'Unknown Album' && prevSong.album != 'Unknown Album') {
      if (song.album == prevSong.album) {
        weight *= 0.7;
      }
    }
  }

  // LOWER PRIORITY: User Preferences
  if (favorites.contains(song.filename)) {
    if (config.personality == ShufflePersonality.consistent) {
      weight *= 1.4;
    } else if (config.personality == ShufflePersonality.explorer) {
      weight *= 1.12;
    } else {
      weight *= config.favoriteMultiplier; // 1.2 default
    }
  }
  if (suggestLess.contains(song.filename)) {
    weight *= 0.2; // 80% penalty
  }

  return max(0.0001, weight);
}

void main() {
  group('Shuffle Logic Tests', () {
    final song1 = Song(
        title: 'Test Song 1',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 's1.mp3',
        url: '');

    final item1 = QueueItem(song: song1);

    test('Recency penalty gives 100% penalty for most recent 2 songs', () {
      final state = const ShuffleState(
        config: ShuffleConfig(historyLimit: 200),
      );

      final history = [
        (
          filename: 's1.mp3',
          timestamp: 1000.0,
          playRatio: 1.0,
          eventType: 'complete'
        )
      ];

      final weight = calculateWeight(item1, null, state, [], [], history);
      expect(weight, equals(0.0001)); // max(0.0001, 0.0) - 100% penalty
    });

    test('Favorite boost increases weight (+20% default)', () {
      final state =
          const ShuffleState(config: ShuffleConfig(favoriteMultiplier: 1.2));
      final weight = calculateWeight(item1, null, state, ['s1.mp3'], [], []);
      expect(weight, equals(1.2));
    });

    test('Suggest-less penalty decreases weight (80% penalty)', () {
      final state = const ShuffleState();
      final weight = calculateWeight(item1, null, state, [], ['s1.mp3'], []);
      expect(weight, closeTo(0.2, 0.0001));
    });

    test('Weights stack correctly', () {
      final state = const ShuffleState(
        config: ShuffleConfig(
            streakBreakerEnabled: true,
            favoriteMultiplier: 1.2,
            historyLimit: 200),
      );

      final history = [
        (
          filename: 'other.mp3',
          timestamp: 100.0,
          playRatio: 1.0,
          eventType: 'complete'
        ),
        (
          filename: 's1.mp3',
          timestamp: 99.0,
          playRatio: 1.0,
          eventType: 'complete'
        ),
      ]; // 2nd last: 100% penalty (1% per 2 songs)

      // s1.mp3 is favorite, 2nd last in history
      // Base: 1.0
      // Recency (historyIndex=1, basePenalty=100%, fullListen=100%): * 0.0 = 0.0
      // Favorite: * 1.2
      // Result: max(0.0001, 0.0) = 0.0001
      final weight =
          calculateWeight(item1, null, state, ['s1.mp3'], [], history);
      expect(weight, equals(0.0001));
    });

    test('Play ratio affects history penalty (low ratio = less penalty)', () {
      final state =
          const ShuffleState(config: ShuffleConfig(historyLimit: 200));

      // Song with low play ratio (0.2) - should get 30% of base penalty
      final historyLowRatio = [
        (
          filename: 's1.mp3',
          timestamp: 100.0,
          playRatio: 0.2,
          eventType: 'skip'
        )
      ];

      // historyIndex=0, basePenalty=100%, but playRatio < 0.25 so multiplier=0.3
      // adjustedPenalty = 100 * 0.3 = 30%
      // weight = 1.0 * (1.0 - 0.30) = 0.7
      final weightLow =
          calculateWeight(item1, null, state, [], [], historyLowRatio);
      expect(weightLow, closeTo(0.7, 0.0001));

      // Song with high play ratio (0.9) - should get full penalty
      final historyHighRatio = [
        (
          filename: 's1.mp3',
          timestamp: 100.0,
          playRatio: 0.9,
          eventType: 'complete'
        )
      ];

      // historyIndex=0, basePenalty=100%, playRatio > 0.8 so multiplier=1.0
      // adjustedPenalty = 100 * 1.0 = 100%
      // weight = 1.0 * (1.0 - 1.0) = 0.0 -> max(0.0001, 0.0) = 0.0001
      final weightHigh =
          calculateWeight(item1, null, state, [], [], historyHighRatio);
      expect(weightHigh, equals(0.0001));
    });

    test('Skip penalty: 3+ skips, low avg ratio (90% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 3, avgRatio: 0.10)};
      // avgRatio = 0.10, so penalty multiplier = 0.10
      // weight = 1.0 * 0.10 = 0.10
      final weight = calculateWeight(item1, null, state, [], [], [], stats);
      expect(weight, closeTo(0.10, 0.001));
    });

    test('Skip penalty: 3+ skips, high avg ratio (no penalty)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 3, avgRatio: 0.5)};
      // avgRatio > 0.25, so no skip penalty applied
      final weight = calculateWeight(item1, null, state, [], [], [], stats);
      expect(weight, equals(1.0));
    });
  });
}

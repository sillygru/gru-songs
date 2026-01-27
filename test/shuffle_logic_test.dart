import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';
import 'package:gru_songs/models/shuffle_config.dart';
import 'dart:math';

// Mock/Simplified version of the weight calculation logic from AudioPlayerManager for isolated testing
double calculateWeight(QueueItem item, QueueItem? prev,
    ShuffleState shuffleState, List<String> favorites, List<String> suggestLess,
    [Map<String, ({int count, double avgRatio})>? skipStats,
    int maxPlayCount = 0]) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;

  // 1. User Preferences
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

  // 2. Streak Breaker (Same Artist/Album) - only in default mode for this mock
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

  // 3. Global Recency Penalty
  if (shuffleState.history.isNotEmpty) {
    int historyIndex =
        shuffleState.history.indexWhere((e) => e.filename == song.filename);
    if (historyIndex != -1 && historyIndex < 100) {
      int n = historyIndex + 1;
      int penaltyPercent = (n == 1) ? 100 : (100 - n);
      if (penaltyPercent > 0) {
        weight *= (1.0 - (penaltyPercent / 100.0));
      }
    }
  }

  // 4. Global Skip Penalty
  if (skipStats != null) {
    final stats = skipStats[song.filename];
    if (stats != null && stats.count >= 3 && stats.avgRatio <= 0.15) {
      weight *= 0.05; // 95% penalty
    }
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

    test('Recency penalty gives 100% penalty for most recent song', () {
      final state = ShuffleState(
        config: const ShuffleConfig(historyLimit: 100),
        history: [
          HistoryEntry(
              filename: 's1.mp3',
              timestamp: DateTime.now().millisecondsSinceEpoch / 1000)
        ],
      );

      final weight = calculateWeight(item1, null, state, [], []);
      expect(weight, equals(0.0001)); // max(0.0001, 0.0)
    });

    test('Favorite boost increases weight (+20% default)', () {
      final state =
          const ShuffleState(config: ShuffleConfig(favoriteMultiplier: 1.2));
      final weight = calculateWeight(item1, null, state, ['s1.mp3'], []);
      expect(weight, equals(1.2));
    });

    test('Suggest-less penalty decreases weight (80% penalty)', () {
      final state = const ShuffleState();
      final weight = calculateWeight(item1, null, state, [], ['s1.mp3']);
      expect(weight, closeTo(0.2, 0.0001));
    });

    test('Weights stack correctly', () {
      final state = ShuffleState(
        config: const ShuffleConfig(
            streakBreakerEnabled: true,
            favoriteMultiplier: 1.2,
            historyLimit: 100),
        history: [
          HistoryEntry(filename: 'other.mp3', timestamp: 100),
          HistoryEntry(filename: 's1.mp3', timestamp: 99),
        ], // 2nd last: 98% penalty
      );

      // s1.mp3 is favorite, 2nd last in history
      // Base: 1.0
      // Favorite: * 1.2 = 1.2
      // Recency (n=2): * 0.02 = 0.024
      final weight = calculateWeight(item1, null, state, ['s1.mp3'], []);
      expect(weight, closeTo(0.024, 0.0001));
    });

    test('Skip penalty: 3+ skips, low avg ratio (95% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 3, avgRatio: 0.10)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, closeTo(0.05, 0.001));
    });

    test('Skip penalty: 3+ skips, high avg ratio (no penalty)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 3, avgRatio: 0.5)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, equals(1.0));
    });
  });
}

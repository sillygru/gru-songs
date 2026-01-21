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
    [Map<String, ({int count, double avgRatio})>? skipStats]) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;

  // 1. Anti-repeat (Recent History)
  if (config.antiRepeatEnabled && shuffleState.history.isNotEmpty) {
    int historyIndex =
        shuffleState.history.indexWhere((e) => e.filename == song.filename);
    if (historyIndex != -1) {
      double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
      weight *= (1.0 - max(0.0, reduction));
    }
  }

  // 2. Streak Breaker (Same Artist/Album)
  if (config.streakBreakerEnabled && prev != null) {
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

  // 3. User Preferences
  if (favorites.contains(song.filename)) {
    weight *= config.favoriteMultiplier;
  }

  if (suggestLess.contains(song.filename)) {
    weight *= config.suggestLessMultiplier;
  }

  // 4. Global Penalties (Multi-tier skip penalty)
  if (skipStats != null) {
    final stats = skipStats[song.filename];
    if (stats != null) {
      if (stats.count >= 4) {
        if (stats.avgRatio < 0.10) {
          weight *= 0.05; // 95% penalty
        }
      } else if (stats.count == 3) {
        weight *= 0.30; // 70% penalty
      } else if (stats.count == 2) {
        weight *= 0.60; // 40% penalty
      } else if (stats.count == 1) {
        weight *= 0.85; // 15% penalty
      }
    }
  }

  return max(0.001, weight);
}

void main() {
  group('Shuffle Logic Tests', () {
    final song1 = Song(
        title: 'Song 1',
        artist: 'Artist A',
        album: 'Album X',
        filename: 's1.mp3',
        url: '');
    final song2 = Song(
        title: 'Song 2',
        artist: 'Artist A',
        album: 'Album X',
        filename: 's2.mp3',
        url: '');
    final songNull = Song(
        title: 'Unknown',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        filename: 'null.mp3',
        url: '');

    final item1 = QueueItem(song: song1);
    final item2 = QueueItem(song: song2);
    final itemNull = QueueItem(song: songNull);

    test('Anti-repeat reduces weight significantly for recent songs', () {
      final state = ShuffleState(
        config: const ShuffleConfig(antiRepeatEnabled: true, historyLimit: 10),
        history: [
          HistoryEntry(
              filename: 's1.mp3',
              timestamp: DateTime.now().millisecondsSinceEpoch / 1000)
        ],
      );

      final weight = calculateWeight(item1, null, state, [], []);
      expect(weight, lessThan(0.1)); // 0.95 reduction
    });

    test('Anti-repeat reduction decays over history', () {
      final stateStart = ShuffleState(
        config: const ShuffleConfig(antiRepeatEnabled: true, historyLimit: 20),
        history: [HistoryEntry(filename: 's1.mp3', timestamp: 100)],
      );
      final weightStart = calculateWeight(item1, null, stateStart, [], []);

      final stateEnd = ShuffleState(
        config: const ShuffleConfig(antiRepeatEnabled: true, historyLimit: 20),
        history: List.generate(
            15,
            (i) => HistoryEntry(
                filename: 'other_$i.mp3', timestamp: 100 + i.toDouble()))
          ..add(HistoryEntry(filename: 's1.mp3', timestamp: 99)),
      );
      final weightEnd = calculateWeight(item1, null, stateEnd, [], []);

      expect(weightEnd, greaterThan(weightStart));
    });

    test('Streak breaker reduces weight for same artist', () {
      final state =
          const ShuffleState(config: ShuffleConfig(streakBreakerEnabled: true));
      final weight =
          calculateWeight(item2, item1, state, [], []); // Both Artist A
      expect(weight, equals(0.5 * 0.7)); // Artist (0.5) * Album (0.7)
    });

    test('Streak breaker handles NULL metadata safely', () {
      final state =
          const ShuffleState(config: ShuffleConfig(streakBreakerEnabled: true));
      final weight = calculateWeight(itemNull, item1, state, [], []);
      expect(weight,
          equals(1.0)); // No reduction because itemNull has 'Unknown Artist'
    });

    test('Favorite boost increases weight', () {
      final state =
          const ShuffleState(config: ShuffleConfig(favoriteMultiplier: 1.5));
      final weight = calculateWeight(item1, null, state, ['s1.mp3'], []);
      expect(weight, equals(1.5));
    });

    test('Suggest-less penalty decreases weight', () {
      final state =
          const ShuffleState(config: ShuffleConfig(suggestLessMultiplier: 0.1));
      final weight = calculateWeight(item1, null, state, [], ['s1.mp3']);
      expect(weight, equals(0.1));
    });

    test('Weights stack correctly', () {
      final state = ShuffleState(
        config: const ShuffleConfig(
            antiRepeatEnabled: true,
            streakBreakerEnabled: true,
            favoriteMultiplier: 2.0,
            historyLimit: 100),
        history: [HistoryEntry(filename: 's1.mp3', timestamp: 100)], // -95%
      );

      // s1.mp3 is favorite but recently played
      // Base: 1.0
      // Anti-repeat (index 0): 1.0 - 0.95 = 0.05
      // Favorite: * 2.0 = 0.1
      final weight = calculateWeight(item1, null, state, ['s1.mp3'], []);
      expect(weight, closeTo(0.1, 0.001));
    });

    test('Weight never reaches zero', () {
      final state = ShuffleState(
        config: const ShuffleConfig(antiRepeatEnabled: true, historyLimit: 10),
        history: [HistoryEntry(filename: 's1.mp3', timestamp: 100)],
      );
      final weight = calculateWeight(item1, null, state, [], ['s1.mp3']);
      expect(weight, greaterThan(0));
    });

    test('Multi-tier skip penalty: 1 skip (15% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 1, avgRatio: 0.5)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, closeTo(0.85, 0.001));
    });

    test('Multi-tier skip penalty: 2 skips (40% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 2, avgRatio: 0.5)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, closeTo(0.60, 0.001));
    });

    test('Multi-tier skip penalty: 3 skips (70% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 3, avgRatio: 0.5)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, closeTo(0.30, 0.001));
    });

    test('Multi-tier skip penalty: 4+ skips, low avg ratio (95% reduction)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 4, avgRatio: 0.05)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, closeTo(0.05, 0.001));
    });

    test('Multi-tier skip penalty: 4+ skips, high avg ratio (no penalty)', () {
      final state = const ShuffleState();
      final stats = {'s1.mp3': (count: 4, avgRatio: 0.5)};
      final weight = calculateWeight(item1, null, state, [], [], stats);
      expect(weight, equals(1.0));
    });
  });
}

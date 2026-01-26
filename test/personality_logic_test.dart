import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';
import 'package:gru_songs/models/shuffle_config.dart';
import 'dart:math';

// Direct copy of logic from AudioPlayerManager for verification
double calculateWeight(
    QueueItem item,
    QueueItem? prev,
    ShuffleState shuffleState,
    List<String> favorites,
    List<String> suggestLess,
    Map<String, int> playCounts,
    int maxPlayCount) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;
  final count = playCounts[song.filename] ?? 0;

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
    weight *= 0.2;
  }

  // 2. Personality Weights
  if (config.personality == ShufflePersonality.explorer) {
    if (count == 0) {
      weight *= 1.2; // 20% reward for never played
    }
  } else if (config.personality == ShufflePersonality.consistent) {
    // Adaptive Threshold
    int threshold = 10;
    if (maxPlayCount < 10) {
      threshold = max(1, (maxPlayCount * 0.7).floor());
    } else if (maxPlayCount < 20) {
      threshold = 5;
    }

    if (count >= threshold && count > 0) {
      weight *= 1.3; // 30% reward for often played
    }
  } else if (config.personality == ShufflePersonality.defaultMode) {
    if (config.streakBreakerEnabled && prev != null) {
      final prevSong = prev.song;
      if (song.artist != 'Unknown Artist' &&
          prevSong.artist != 'Unknown Artist' &&
          song.artist == prevSong.artist) {
        weight *= 0.5;
      }
      if (song.album != 'Unknown Album' &&
          prevSong.album != 'Unknown Album' &&
          song.album == prevSong.album) {
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

  return max(0.0001, weight);
}

void main() {
  final songNew = Song(
      title: 'New',
      artist: 'A',
      album: 'X',
      filename: 'new.mp3',
      url: '',
      playCount: 0);
  final songFrequent = Song(
      title: 'Frequent',
      artist: 'A',
      album: 'X',
      filename: 'freq.mp3',
      url: '',
      playCount: 60);
  final songFav = Song(
      title: 'Fav',
      artist: 'B',
      album: 'Y',
      filename: 'fav.mp3',
      url: '',
      playCount: 20);

  final itemNew = QueueItem(song: songNew);
  final itemFreq = QueueItem(song: songFrequent);
  final itemFav = QueueItem(song: songFav);

  group('Personality: EXPLORER', () {
    final config =
        const ShuffleConfig(personality: ShufflePersonality.explorer);
    final state = ShuffleState(config: config);

    test('Explorer gives 20% boost to unplayed songs', () {
      final weight =
          calculateWeight(itemNew, null, state, [], [], {'new.mp3': 0}, 60);
      expect(weight, closeTo(1.2, 0.001));
    });

    test('Explorer favorite multiplier is 1.12', () {
      final weight = calculateWeight(
          itemFav, null, state, ['fav.mp3'], [], {'fav.mp3': 20}, 60);
      expect(weight, closeTo(1.12, 0.001));
    });
  });

  group('Personality: CONSISTENT', () {
    final config =
        const ShuffleConfig(personality: ShufflePersonality.consistent);
    final state = ShuffleState(config: config);

    test('Consistent gives boost to often played songs', () {
      final weight =
          calculateWeight(itemFreq, null, state, [], [], {'freq.mp3': 60}, 60);
      expect(weight, closeTo(1.3, 0.001));
    });

    test('Consistent favorite multiplier is 1.4', () {
      final weight = calculateWeight(
          itemFav, null, state, ['fav.mp3'], [], {'fav.mp3': 20}, 60);
      // 1.4 (fav) * 1.3 (often played) = 1.82
      expect(weight, closeTo(1.82, 0.001));
    });

    test('Consistent adapts to new users (maxPlayCount < 10)', () {
      // maxPlayCount = 2, threshold = floor(2 * 0.7) = 1
      final weight =
          calculateWeight(itemFav, null, state, [], [], {'fav.mp3': 1}, 2);
      expect(weight, closeTo(1.3, 0.001));
    });
  });
}

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
    Map<String, int> playCounts,
    int maxPlayCount,
    List<
            ({
              String filename,
              double timestamp,
              double playRatio,
              String eventType
            })>
        playHistory) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;
  final count = playCounts[song.filename] ?? 0;

  // HIERARCHY 1: Global Recency Penalty (applied first)
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

  // HIERARCHY 3: Personality Weights
  if (config.personality == ShufflePersonality.explorer) {
    if (maxPlayCount > 0) {
      final playRatio = count / maxPlayCount;
      if (playRatio <= 0.4) {
        double explorerReward = 1.0 + (1.0 - (playRatio / 0.4));
        weight *= explorerReward;
      }
    } else if (count == 0) {
      weight *= 2.0;
    }
  } else if (config.personality == ShufflePersonality.consistent) {
    int threshold = 10;
    if (maxPlayCount < 10) {
      threshold = max(1, (maxPlayCount * 0.7).floor());
    } else if (maxPlayCount < 20) {
      threshold = 5;
    }

    if (count >= threshold && count > 0) {
      weight *= 1.3;
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

  // LOWER PRIORITY: User Preferences
  if (favorites.contains(song.filename)) {
    if (config.personality == ShufflePersonality.consistent) {
      weight *= 1.4;
    } else if (config.personality == ShufflePersonality.explorer) {
      weight *= 1.12;
    } else {
      weight *= config.favoriteMultiplier;
    }
  }
  if (suggestLess.contains(song.filename)) {
    weight *= 0.2;
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

    test('Explorer gives 2x boost to unplayed songs', () {
      final weight =
          calculateWeight(itemNew, null, state, [], [], {'new.mp3': 0}, 60, []);
      expect(weight, closeTo(2.0, 0.001));
    });

    test(
        'Explorer favorite multiplier is 1.12, plus explorer boost for low play ratio',
        () {
      final weight = calculateWeight(
          itemFav, null, state, ['fav.mp3'], [], {'fav.mp3': 20}, 60, []);
      // playRatio = 20/60 = 0.33 (< 0.4)
      // explorerReward = 1.0 + (1.0 - (0.33/0.4)) = 1.0 + 0.175 = 1.175
      // favorite = 1.12
      // total = 1.175 * 1.12 = 1.316
      expect(weight, closeTo(1.316, 0.02));
    });
  });

  group('Personality: CONSISTENT', () {
    final config =
        const ShuffleConfig(personality: ShufflePersonality.consistent);
    final state = ShuffleState(config: config);

    test('Consistent gives boost to often played songs', () {
      final weight = calculateWeight(
          itemFreq, null, state, [], [], {'freq.mp3': 60}, 60, []);
      expect(weight, closeTo(1.3, 0.001));
    });

    test('Consistent favorite multiplier is 1.4, plus often-played boost', () {
      final weight = calculateWeight(
          itemFav, null, state, ['fav.mp3'], [], {'fav.mp3': 20}, 60, []);
      // fav.mp3 has 20 plays, threshold is 10, so it gets often-played boost
      // often-played = 1.3
      // favorite = 1.4
      // total = 1.3 * 1.4 = 1.82
      expect(weight, closeTo(1.82, 0.001));
    });

    test('Consistent adapts to new users (maxPlayCount < 10)', () {
      // maxPlayCount = 2, threshold = floor(2 * 0.7) = 1
      final weight =
          calculateWeight(itemFav, null, state, [], [], {'fav.mp3': 1}, 2, []);
      expect(weight, closeTo(1.3, 0.001));
    });
  });
}

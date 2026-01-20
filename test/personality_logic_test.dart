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
    Map<String, int> playCounts) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;
  final count = playCounts[song.filename] ?? 0;

  // --- Personality: DEFAULT ---
  if (config.personality == ShufflePersonality.defaultMode) {
    if (favorites.contains(song.filename)) {
      weight *= config.favoriteMultiplier;
    }
    if (suggestLess.contains(song.filename)) {
      weight *= config.suggestLessMultiplier;
    }

    if (config.antiRepeatEnabled && shuffleState.history.isNotEmpty) {
      int historyIndex =
          shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1) {
        double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
        weight *= (1.0 - max(0.0, reduction));
      }
    }

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
  // --- Personality: EXPLORER ---
  else if (config.personality == ShufflePersonality.explorer) {
    if (count == 0) {
      weight *= 50.0;
    } else if (count < 5) {
      weight *= 5.0;
    } else if (count > 50) {
      weight *= 0.01;
    } else if (count > 15) {
      weight *= 0.1;
    }

    if (favorites.contains(song.filename)) weight *= 1.1;
    if (suggestLess.contains(song.filename)) weight *= 0.001;

    if (shuffleState.history.isNotEmpty) {
      int historyIndex =
          shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1) {
        double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
        weight *= (1.0 - max(0.0, reduction));
      }
    }
  }
  // --- Personality: CONSISTENT ---
  else if (config.personality == ShufflePersonality.consistent) {
    if (favorites.contains(song.filename)) weight *= 3.0;

    if (count > 10) weight *= 1.5;
    if (count > 50) weight *= 2.0;

    if (shuffleState.history.isNotEmpty) {
      int historyIndex =
          shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1) {
        if (historyIndex < 10) {
          weight *= 0.05;
        }
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

    test('Explorer gives massive boost to unplayed songs', () {
      final weight =
          calculateWeight(itemNew, null, state, [], [], {'new.mp3': 0});
      expect(weight, equals(50.0));
    });

    test('Explorer penalizes overplayed songs', () {
      final weight =
          calculateWeight(itemFreq, null, state, [], [], {'freq.mp3': 60});
      expect(weight, equals(0.01));
    });

    test('Explorer still applies anti-repeat', () {
      final stateWithHistory = state.copyWith(
          history: [HistoryEntry(filename: 'new.mp3', timestamp: 100)]);
      final weight = calculateWeight(
          itemNew, null, stateWithHistory, [], [], {'new.mp3': 0});
      // 50.0 * (1.0 - 0.95) = 2.5
      expect(weight, closeTo(2.5, 0.001));
    });
  });

  group('Personality: CONSISTENT', () {
    final config =
        const ShuffleConfig(personality: ShufflePersonality.consistent);
    final state = ShuffleState(config: config);

    test('Consistent gives boost to favorites', () {
      final weight = calculateWeight(
          itemFav, null, state, ['fav.mp3'], [], {'fav.mp3': 20});
      // favorite (3.0) * playCount > 10 (1.5) = 4.5
      expect(weight, equals(4.5));
    });

    test('Consistent gives extra boost to very overplayed songs', () {
      final weight =
          calculateWeight(itemFreq, null, state, [], [], {'freq.mp3': 60});
      // playCount > 10 (1.5) * playCount > 50 (2.0) = 3.0
      expect(weight, equals(3.0));
    });

    test('Consistent has relaxed anti-repeat (only last 10)', () {
      // Index 5 in history (less than 10)
      final stateRecent = state.copyWith(
          history: List.generate(
              5, (i) => HistoryEntry(filename: 'other$i.mp3', timestamp: 1.0))
            ..add(HistoryEntry(filename: 'fav.mp3', timestamp: 0.0)));
      final weightRecent =
          calculateWeight(itemFav, null, stateRecent, [], [], {'fav.mp3': 20});
      // playCount > 10 (1.5) * anti-repeat (0.05) = 0.075
      expect(weightRecent, closeTo(0.075, 0.001));

      // Index 15 in history (greater than 10)
      final stateOld = state.copyWith(
          history: List.generate(
              15, (i) => HistoryEntry(filename: 'other$i.mp3', timestamp: 1.0))
            ..add(HistoryEntry(filename: 'fav.mp3', timestamp: 0.0)));
      final weightOld =
          calculateWeight(itemFav, null, stateOld, [], [], {'fav.mp3': 20});
      // playCount > 10 (1.5) * NO anti-repeat (1.0) = 1.5
      expect(weightOld, equals(1.5));
    });
  });
}

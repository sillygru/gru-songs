import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';
import 'package:gru_songs/models/shuffle_config.dart';
import 'dart:math';

// Extraction of the logic to be tested
double calculateWeight(QueueItem item, QueueItem? prev, ShuffleState shuffleState, List<String> favorites, List<String> suggestLess) {
  double weight = 1.0;
  final song = item.song;
  final config = shuffleState.config;

  if (config.antiRepeatEnabled && shuffleState.history.isNotEmpty) {
    int historyIndex = shuffleState.history.indexOf(song.filename);
    if (historyIndex != -1) {
      double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
      weight *= (1.0 - max(0.0, reduction));
    }
  }

  if (config.streakBreakerEnabled && prev != null) {
    final prevSong = prev.song;
    if (song.artist != 'Unknown Artist' && prevSong.artist != 'Unknown Artist') {
      if (song.artist == prevSong.artist) weight *= 0.5;
    }
    if (song.album != 'Unknown Album' && prevSong.album != 'Unknown Album') {
      if (song.album == prevSong.album) weight *= 0.7;
    }
  }

  if (favorites.contains(song.filename)) {
    // print('Favorite boost for ${song.filename}: ${config.favoriteMultiplier}');
    weight *= config.favoriteMultiplier;
  }
  if (suggestLess.contains(song.filename)) weight *= config.suggestLessMultiplier;

  return max(0.001, weight);
}

List<QueueItem> weightedShuffle(List<QueueItem> items, ShuffleState state, List<String> favs, List<String> sl, Random random, {QueueItem? lastItem, bool debug = false}) {
  if (items.isEmpty) return [];
  final result = <QueueItem>[];
  final remaining = List<QueueItem>.from(items);
  QueueItem? prev = lastItem;

  int iteration = 0;
  while (remaining.isNotEmpty) {
    final weights = remaining.map((item) => calculateWeight(item, prev, state, favs, sl)).toList();
    final totalWeight = weights.fold(0.0, (a, b) => a + b);
    
    if (debug && iteration == 0) {
      print('Items: ${remaining.map((e) => e.song.filename).toList()}');
      print('Weights: $weights');
      print('Total Weight: $totalWeight');
    }
    
    double randomValue = random.nextDouble() * totalWeight;
    if (debug && iteration == 0) {
      print('Random Value: $randomValue');
    }
    int selectedIdx = -1;
    double cumulativeWeight = 0.0;
    for (int i = 0; i < weights.length; i++) {
      cumulativeWeight += weights[i];
      if (randomValue <= cumulativeWeight) {
        selectedIdx = i;
        break;
      }
    }
    if (selectedIdx == -1) selectedIdx = remaining.length - 1;
    if (debug && iteration == 0) {
      print('Selected Index: $selectedIdx (${remaining[selectedIdx].song.filename})');
    }
    final selected = remaining.removeAt(selectedIdx);
    result.add(selected);
    prev = selected;
    iteration++;
  }
  return result;
}

void main() {
  test('Distribution test: Favorites should appear earlier more often', () {
    final songs = List.generate(20, (i) => Song(
      title: 'Song $i', artist: 'Artist $i', album: 'Album $i', filename: 's$i.mp3', url: ''
    ));
    final items = songs.map((s) => QueueItem(song: s)).toList();
    final favorites = ['s0.mp3']; // Only s0 is favorite
    final state = const ShuffleState(config: ShuffleConfig(enabled: true, favoriteMultiplier: 2.0));

    int s0FirstCount = 0;
    const iterations = 2000;
    final random = Random(42);

    for (int i = 0; i < iterations; i++) {
      final shuffled = weightedShuffle(items, state, favorites, [], random, debug: i == 0);
      if (shuffled.first.song.filename == 's0.mp3') {
        s0FirstCount++;
      }
    }

    // With 20 songs, uniform chance is 5%. With 2x weight, it should be ~2 / (2 + 19) = 2/21 ~= 9.5%
    print('s0 (favorite) appeared first $s0FirstCount times out of $iterations');
    expect(s0FirstCount, greaterThan(120)); 
    expect(s0FirstCount, lessThan(300));
  });

  test('Distribution test: Suggest-less should appear later more often', () {
    final songs = List.generate(10, (i) => Song(
      title: 'Song $i', artist: 'Artist $i', album: 'Album $i', filename: 's$i.mp3', url: ''
    ));
    final items = songs.map((s) => QueueItem(song: s)).toList();
    final suggestLess = ['s0.mp3'];
    final state = const ShuffleState(config: ShuffleConfig(enabled: true, suggestLessMultiplier: 0.2));

    int s0FirstCount = 0;
    const iterations = 1000;
    final random = Random(123);

    for (int i = 0; i < iterations; i++) {
      final shuffled = weightedShuffle(items, state, [], suggestLess, random);
      if (shuffled.first.song.filename == 's0.mp3') {
        s0FirstCount++;
      }
    }

    // Expected probability ~ 0.2 / (0.2 + 9) = 0.2/9.2 ~= 2%
    print('s0 (suggest-less) appeared first $s0FirstCount times out of $iterations');
    expect(s0FirstCount, lessThan(50));
  });
}

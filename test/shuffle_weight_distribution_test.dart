import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';
import 'package:wispie/models/shuffle_config.dart';
import 'package:wispie/domain/services/shuffle_weight_service.dart';
import 'dart:math';

List<QueueItem> weightedShuffle(List<QueueItem> items, ShuffleState state,
    List<String> favs, List<String> sl, Random random,
    {QueueItem? lastItem, bool debug = false}) {
  if (items.isEmpty) return [];
  final result = <QueueItem>[];
  final remaining = List<QueueItem>.from(items);
  QueueItem? prev = lastItem;

  final config = state.config;
  final isCustomMode = config.personality == ShufflePersonality.custom;

  int iteration = 0;
  while (remaining.isNotEmpty) {
    final weights = remaining.map((item) {
      final isFav = favs.contains(item.song.filename);
      final isSl = sl.contains(item.song.filename);
      return calculateWeight(
        item: item,
        prev: prev,
        config: config,
        isFavorite: isFav,
        isSuggestLess: isSl,
        playCount: 0,
        maxPlayCount: 0,
        skipCount: isCustomMode ? 0 : null,
        skipAvgRatio: isCustomMode ? 0.5 : null,
      );
    }).toList();
    final totalWeight = weights.fold(0.0, (a, b) => a + b);

    if (debug && iteration == 0) {
      debugPrint('Items: ${remaining.map((e) => e.song.filename).toList()}');
      debugPrint('Weights: $weights');
      debugPrint('Total Weight: $totalWeight');
    }

    double randomValue = random.nextDouble() * totalWeight;
    if (debug && iteration == 0) {
      debugPrint('Random Value: $randomValue');
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
      debugPrint(
          'Selected Index: $selectedIdx (${remaining[selectedIdx].song.filename})');
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
    final songs = List.generate(
        20,
        (i) => Song(
            title: 'Song $i',
            artist: 'Artist $i',
            album: 'Album $i',
            filename: 's$i.mp3',
            url: ''));
    final items = songs.map((s) => QueueItem(song: s)).toList();
    final favorites = ['s0.mp3'];

    // Use custom mode with favoritesWeight to get weighted behavior
    final state = ShuffleState(
        config: const ShuffleConfig(
      enabled: true,
      personality: ShufflePersonality.custom,
      favoritesWeight: 100, // 2x weight for favorites
    ));

    int s0FirstCount = 0;
    const iterations = 2000;
    final random = Random(42);

    for (int i = 0; i < iterations; i++) {
      final shuffled =
          weightedShuffle(items, state, favorites, [], random, debug: i == 0);
      if (shuffled.first.song.filename == 's0.mp3') {
        s0FirstCount++;
      }
    }

    // With 20 songs and 2x weight: expected ~ (2) / (2 + 19) = 2/21 ~= 9.5%
    debugPrint(
        's0 (favorite) appeared first $s0FirstCount times out of $iterations');
    expect(s0FirstCount, greaterThan(120));
    expect(s0FirstCount, lessThan(300));
  });

  test('Distribution test: Suggest-less should appear later more often', () {
    final songs = List.generate(
        10,
        (i) => Song(
            title: 'Song $i',
            artist: 'Artist $i',
            album: 'Album $i',
            filename: 's$i.mp3',
            url: ''));
    final items = songs.map((s) => QueueItem(song: s)).toList();
    final suggestLess = ['s0.mp3'];

    // Use custom mode with suggestLessWeight to get weighted behavior
    // suggestLessWeight = 80 -> multiplier = 1.0 + (-80/100) = 0.2
    final state = ShuffleState(
        config: const ShuffleConfig(
      enabled: true,
      personality: ShufflePersonality.custom,
      suggestLessWeight: 80, // 0.2x weight
    ));

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
    debugPrint(
        's0 (suggest-less) appeared first $s0FirstCount times out of $iterations');
    expect(s0FirstCount, lessThan(50));
  });
}

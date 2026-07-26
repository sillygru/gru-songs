import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/shuffle_selector.dart';
import 'package:wispie/domain/services/song_affinity_service.dart';
import 'package:wispie/models/shuffle_config.dart';

/// End-to-end distribution checks over a synthetic library shaped like a real
/// one: a long tail of songs the listener rarely touches, a mid band they play
/// occasionally, and a small set they genuinely love.
///
/// These run the real pipeline — raw play events through [computeAffinities]
/// and on into [selectSeed] / [orderQueue] — rather than hand-built scores, so
/// they catch a regression anywhere along it.

final _now = DateTime.utc(2026, 1, 1);

double _daysAgo(num days) =>
    _now.subtract(Duration(hours: (days * 24).round())).millisecondsSinceEpoch /
    1000.0;

const int _lovedCount = 20;
const int _midCount = 80;
const int _tailCount = 400;

String _loved(int i) => 'loved$i.mp3';
String _mid(int i) => 'mid$i.mp3';
String _tail(int i) => 'tail$i.mp3';

/// ~500 songs and a few thousand play events, in the spirit of a library with
/// 140 hours behind it.
List<PlayEventRecord> _history() {
  final rng = Random(42);
  final events = <PlayEventRecord>[];

  // Loved: played often and recently, nearly always to completion.
  for (var i = 0; i < _lovedCount; i++) {
    for (var p = 0; p < 60; p++) {
      events.add(PlayEventRecord(
        filename: _loved(i),
        timestamp: _daysAgo(rng.nextDouble() * 120),
        playRatio: 0.9 + rng.nextDouble() * 0.1,
      ));
    }
  }

  // Mid: occasional, mixed completion.
  for (var i = 0; i < _midCount; i++) {
    for (var p = 0; p < 8; p++) {
      events.add(PlayEventRecord(
        filename: _mid(i),
        timestamp: _daysAgo(rng.nextDouble() * 300),
        playRatio: 0.3 + rng.nextDouble() * 0.6,
      ));
    }
  }

  // Tail: tried once or twice long ago, usually abandoned immediately.
  for (var i = 0; i < _tailCount; i++) {
    for (var p = 0; p < 2; p++) {
      events.add(PlayEventRecord(
        filename: _tail(i),
        timestamp: _daysAgo(200 + rng.nextDouble() * 150),
        playRatio: rng.nextDouble() * 0.08,
      ));
    }
  }

  return events;
}

List<ShuffleCandidate<String>> _candidates(
  Map<String, SongAffinity> affinities, {
  Set<String> favorites = const {},
}) {
  final all = <String>[
    for (var i = 0; i < _lovedCount; i++) _loved(i),
    for (var i = 0; i < _midCount; i++) _mid(i),
    for (var i = 0; i < _tailCount; i++) _tail(i),
  ];

  return [
    for (final filename in all)
      ShuffleCandidate<String>(
        payload: filename,
        artist: 'Artist ${filename.hashCode % 60}',
        album: 'Album ${filename.hashCode % 120}',
        affinity: affinities[filename] ?? SongAffinity.unknown,
        isFavorite: favorites.contains(filename),
      ),
  ];
}

void main() {
  final affinities = computeAffinities(events: _history(), now: _now);
  final candidates = _candidates(affinities);
  final total = _lovedCount + _midCount + _tailCount;

  /// Share of seed draws landing on the loved band.
  double lovedSeedShare(ShuffleWeights weights, {int trials = 8000}) {
    final rng = Random(99);
    var hits = 0;
    for (var i = 0; i < trials; i++) {
      if (selectSeed(candidates, weights, random: rng)!
          .payload
          .startsWith('loved')) {
        hits++;
      }
    }
    return hits / trials;
  }

  group('affinity model over a realistic library', () {
    test('separates the three listening bands', () {
      expect(affinities[_loved(0)]!.affinity,
          greaterThan(affinities[_mid(0)]!.affinity));
      expect(affinities[_mid(0)]!.affinity,
          greaterThan(affinities[_tail(0)]!.affinity));
    });

    test('the abandoned tail bottoms out', () {
      final tailScores = [
        for (var i = 0; i < _tailCount; i++) affinities[_tail(i)]!.affinity,
      ];
      expect(tailScores.every((s) => s < 0.05), isTrue);
    });
  });

  group('seed selection', () {
    test('overwhelmingly beats the uniform pick it replaced', () {
      // Uniform over 500 songs would give the 20 loved songs 4%.
      final uniform = _lovedCount / total;
      final share =
          lovedSeedShare(ShuffleWeights.forPersonality(const ShuffleConfig()));

      expect(share, greaterThan(uniform * 5));
    });

    test('personalities order the concentration as advertised', () {
      final consistent = lovedSeedShare(ShuffleWeights.forPersonality(
          const ShuffleConfig(personality: ShufflePersonality.consistent)));
      final normal =
          lovedSeedShare(ShuffleWeights.forPersonality(const ShuffleConfig()));
      final explorer = lovedSeedShare(ShuffleWeights.forPersonality(
          const ShuffleConfig(personality: ShufflePersonality.explorer)));

      expect(consistent, greaterThan(normal));
      expect(normal, greaterThan(explorer));
    });

    test('favorites lift a song out of the tail', () {
      // A tail song the listener explicitly favorited should now outrank its
      // untouched neighbours despite identical play history.
      final withFavorite = computeAffinities(
        events: _history(),
        now: _now,
        favorites: {_tail(0)},
      );
      final pool = _candidates(withFavorite, favorites: {_tail(0)});
      final weights = ShuffleWeights.forPersonality(const ShuffleConfig());

      final favoriteIndex = pool.indexWhere((c) => c.payload == _tail(0));
      final neighbourIndex = pool.indexWhere((c) => c.payload == _tail(1));

      expect(scoreCandidate(pool[favoriteIndex], weights),
          greaterThan(scoreCandidate(pool[neighbourIndex], weights)));
    });
  });

  group('queue ordering', () {
    test('preserves the whole library exactly once', () {
      final ordered = orderQueue(
        candidates,
        ShuffleWeights.forPersonality(const ShuffleConfig()),
        random: Random(21),
      );

      expect(ordered.length, total);
      expect(ordered.map((c) => c.payload).toSet().length, total);
    });

    test('front-loads the loved band', () {
      final ordered = orderQueue(
        candidates,
        ShuffleWeights.forPersonality(const ShuffleConfig()),
        random: Random(21),
      );

      final lovedInFirstFifty =
          ordered.take(50).where((c) => c.payload.startsWith('loved')).length;

      // Chance would place 20/500 * 50 = 2 of them in the opening fifty.
      expect(lovedInFirstFifty, greaterThan(6));
    });

    test('keeps same-artist tracks apart in the opening stretch', () {
      final ordered = orderQueue(
        candidates,
        ShuffleWeights.forPersonality(const ShuffleConfig()),
        random: Random(21),
      );

      var adjacent = 0;
      for (var i = 1; i < 100; i++) {
        if (ordered[i].artist == ordered[i - 1].artist) adjacent++;
      }
      expect(adjacent, lessThan(5));
    });

    test('a burnt-out song ranks below a steadily loved one', () {
      // Same total plays; one crammed into the last two days, one spread out.
      final events = <PlayEventRecord>[
        for (var p = 0; p < 30; p++)
          PlayEventRecord(
            filename: 'binge.mp3',
            timestamp: _daysAgo(p * 0.05),
            playRatio: 1.0,
          ),
        for (var p = 0; p < 30; p++)
          PlayEventRecord(
            filename: 'steady.mp3',
            timestamp: _daysAgo(p * 2.0),
            playRatio: 1.0,
          ),
      ];

      final model = computeAffinities(events: events, now: _now);
      final weights = ShuffleWeights.forPersonality(const ShuffleConfig());

      ShuffleCandidate<String> asCandidate(String name) =>
          ShuffleCandidate<String>(
            payload: name,
            artist: name,
            album: name,
            affinity: model[name]!,
          );

      expect(scoreCandidate(asCandidate('binge.mp3'), weights),
          lessThan(scoreCandidate(asCandidate('steady.mp3'), weights)));
    });
  });
}

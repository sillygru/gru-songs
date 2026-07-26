import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/shuffle_selector.dart';
import 'package:wispie/domain/services/song_affinity_service.dart';
import 'package:wispie/models/shuffle_config.dart';

SongAffinity _affinity({
  double affinity = 0.5,
  double saturation = 0.0,
  double skipRate = 0.0,
  int playCount = 5,
}) =>
    SongAffinity(
      affinity: affinity,
      recentSaturation: saturation,
      completionRate: 1.0 - skipRate,
      skipRate: skipRate,
      playCount: playCount,
      lastPlayedAt: null,
    );

ShuffleCandidate<String> _candidate(
  String name, {
  double affinity = 0.5,
  double saturation = 0.0,
  double skipRate = 0.0,
  int playCount = 5,
  String artist = 'Artist',
  String album = 'Album',
  bool isFavorite = false,
  bool isSuggestLess = false,
  bool isInPlaylist = false,
  int? historyIndex,
}) =>
    ShuffleCandidate<String>(
      payload: name,
      artist: artist,
      album: album,
      affinity: _affinity(
        affinity: affinity,
        saturation: saturation,
        skipRate: skipRate,
        playCount: playCount,
      ),
      isFavorite: isFavorite,
      isSuggestLess: isSuggestLess,
      isInPlaylist: isInPlaylist,
      historyIndex: historyIndex,
    );

void main() {
  final defaults = ShuffleWeights.forPersonality(const ShuffleConfig());

  group('scoreCandidate', () {
    test('a loved song outscores an indifferent one', () {
      final loved = scoreCandidate(_candidate('a', affinity: 0.95), defaults);
      final meh = scoreCandidate(_candidate('b', affinity: 0.1), defaults);
      expect(loved, greaterThan(meh));
    });

    test('favorites are boosted in the default personality', () {
      // The old engine gated the favorite boost behind custom mode, so this
      // was a no-op in three of the four personalities.
      final favorite =
          scoreCandidate(_candidate('a', isFavorite: true), defaults);
      final plain = scoreCandidate(_candidate('b'), defaults);
      expect(favorite, greaterThan(plain));
    });

    test('favorites are boosted in every personality', () {
      for (final personality in ShufflePersonality.values) {
        final weights = ShuffleWeights.forPersonality(
          ShuffleConfig(personality: personality),
        );
        final favorite =
            scoreCandidate(_candidate('a', isFavorite: true), weights);
        final plain = scoreCandidate(_candidate('b'), weights);
        expect(favorite, greaterThan(plain), reason: '$personality');
      }
    });

    test('"suggest less" pushes a song down', () {
      final suppressed =
          scoreCandidate(_candidate('a', isSuggestLess: true), defaults);
      final plain = scoreCandidate(_candidate('b'), defaults);
      expect(suppressed, lessThan(plain));
    });

    test('heavy listening raises a song rather than penalizing it', () {
      // Directly inverts the old playCount/maxPlayCount penalty, which made
      // the most-played songs the least likely to be chosen.
      final wellLoved = scoreCandidate(
          _candidate('a', affinity: 1.0, playCount: 200), defaults);
      final barelyTouched = scoreCandidate(
          _candidate('b', affinity: 0.05, playCount: 1), defaults);
      expect(wellLoved, greaterThan(barelyTouched));
    });

    test('anti-repeat is strongest for the song just played', () {
      final justPlayed =
          scoreCandidate(_candidate('a', historyIndex: 0), defaults);
      final middling =
          scoreCandidate(_candidate('b', historyIndex: 100), defaults);
      final absent = scoreCandidate(_candidate('c'), defaults);

      expect(justPlayed, lessThan(middling));
      expect(middling, lessThan(absent));
    });

    test('anti-repeat fades to nothing at the edge of the history window', () {
      final atEdge =
          scoreCandidate(_candidate('a', historyIndex: 199), defaults);
      final outside = scoreCandidate(_candidate('b'), defaults);
      expect(atEdge, closeTo(outside, outside * 0.02));
    });

    test('anti-repeat scales with the configured history limit', () {
      // A hardcoded bucket ladder ignored historyLimit entirely.
      final short =
          ShuffleWeights.forPersonality(const ShuffleConfig(historyLimit: 20));
      final long =
          ShuffleWeights.forPersonality(const ShuffleConfig(historyLimit: 400));

      final atTen = _candidate('a', historyIndex: 10);
      expect(scoreCandidate(atTen, short),
          greaterThan(scoreCandidate(atTen, long)));
    });

    test('disabling anti-repeat removes the recency penalty', () {
      final weights = ShuffleWeights.forPersonality(
          const ShuffleConfig(antiRepeatEnabled: false));
      expect(scoreCandidate(_candidate('a', historyIndex: 0), weights),
          scoreCandidate(_candidate('b'), weights));
    });

    test('burnout damps a song hammered this week', () {
      final binged = scoreCandidate(
          _candidate('a', affinity: 0.9, saturation: 3.0), defaults);
      final steady = scoreCandidate(_candidate('b', affinity: 0.9), defaults);
      expect(binged, lessThan(steady));
    });

    test('burnout damps but never buries', () {
      final binged = scoreCandidate(
          _candidate('a', affinity: 1.0, saturation: 5.0), defaults);
      final disliked = scoreCandidate(_candidate('b', affinity: 0.0), defaults);
      expect(binged, greaterThan(disliked));
    });

    test('a habitually skipped song is pushed down', () {
      final skipped = scoreCandidate(
          _candidate('a', affinity: 0.6, skipRate: 0.9), defaults);
      final kept = scoreCandidate(_candidate('b', affinity: 0.6), defaults);
      expect(skipped, lessThan(kept));
    });

    test('every score stays strictly positive so nothing is unreachable', () {
      final worst = _candidate(
        'a',
        affinity: 0.0,
        skipRate: 1.0,
        saturation: 10.0,
        playCount: 500,
        isSuggestLess: true,
        historyIndex: 0,
      );
      final score = scoreCandidate(worst, defaults);
      expect(score, greaterThan(0.0));
      expect(score, isNot(isNaN));
    });
  });

  group('selectSeed', () {
    test('returns null only for an empty pool', () {
      expect(selectSeed(<ShuffleCandidate<String>>[], defaults), isNull);
      expect(selectSeed([_candidate('a')], defaults)?.payload, 'a');
    });

    /// Fraction of seed draws that landed on 'loved'.
    double lovedShare(
      List<ShuffleCandidate<String>> candidates,
      ShuffleWeights weights, {
      int trials = 10000,
      int seed = 7,
    }) {
      final rng = Random(seed);
      var hits = 0;
      for (var i = 0; i < trials; i++) {
        if (selectSeed(candidates, weights, random: rng)!.payload == 'loved') {
          hits++;
        }
      }
      return hits / trials;
    }

    /// One clear favourite among 49 songs the listener has heard but is
    /// lukewarm on — the shape of a real library after 140 hours.
    List<ShuffleCandidate<String>> library() => [
          _candidate('loved', affinity: 1.0, playCount: 100),
          for (var i = 0; i < 49; i++)
            _candidate('filler$i', affinity: 0.1, playCount: 5),
        ];

    test('is biased toward songs the listener actually likes', () {
      // The regression guard for the headline bug: the shuffle button used to
      // pick its opening song with a uniform nextInt, ignoring all weighting.
      // Uniform would be 1/50 = 2%.
      expect(lovedShare(library(), defaults), greaterThan(0.15));
    });

    test('consistent concentrates on the favourite harder than explorer', () {
      final consistent = ShuffleWeights.forPersonality(
          const ShuffleConfig(personality: ShufflePersonality.consistent));
      final explorer = ShuffleWeights.forPersonality(
          const ShuffleConfig(personality: ShufflePersonality.explorer));

      final consistentShare = lovedShare(library(), consistent);
      final defaultShare = lovedShare(library(), defaults);
      final explorerShare = lovedShare(library(), explorer);

      expect(consistentShare, greaterThan(defaultShare));
      expect(defaultShare, greaterThan(explorerShare));
    });

    test('never-played songs still get real discovery weight', () {
      // Novelty is a feature, not leakage: a library of untouched songs should
      // not be crowded out by the one song with history.
      final candidates = [
        _candidate('loved', affinity: 1.0, playCount: 100),
        for (var i = 0; i < 49; i++)
          _candidate('fresh$i', affinity: 0.0, playCount: 0),
      ];

      final share = lovedShare(candidates, defaults);
      expect(share, greaterThan(0.03));
      expect(share, lessThan(0.5));
    });

    test('still reaches the tail of the library eventually', () {
      final candidates = [
        _candidate('loved', affinity: 1.0),
        for (var i = 0; i < 20; i++) _candidate('tail$i', affinity: 0.0),
      ];

      final rng = Random(11);
      final seen = <String>{};
      for (var i = 0; i < 5000; i++) {
        seen.add(selectSeed(candidates, defaults, random: rng)!.payload);
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('orderQueue', () {
    test('returns every candidate exactly once', () {
      final candidates = [
        for (var i = 0; i < 60; i++) _candidate('s$i', artist: 'Artist$i'),
      ];
      final ordered = orderQueue(candidates, defaults, random: Random(3));

      expect(ordered.length, candidates.length);
      expect(ordered.map((c) => c.payload).toSet().length, candidates.length);
    });

    test('handles trivial pools without touching the RNG', () {
      expect(orderQueue(<ShuffleCandidate<String>>[], defaults), isEmpty);
      expect(orderQueue([_candidate('a')], defaults).single.payload, 'a');
    });

    test('front-loads high-affinity songs on average', () {
      final candidates = [
        for (var i = 0; i < 25; i++)
          _candidate('loved$i', affinity: 1.0, artist: 'A$i'),
        for (var i = 0; i < 25; i++)
          _candidate('meh$i', affinity: 0.02, artist: 'B$i'),
      ];

      final rng = Random(5);
      var lovedInFirstTen = 0;
      const runs = 200;
      for (var r = 0; r < runs; r++) {
        final ordered = orderQueue(candidates, defaults, random: rng);
        lovedInFirstTen +=
            ordered.take(10).where((c) => c.payload.startsWith('loved')).length;
      }

      // Chance would be 5 of 10.
      expect(lovedInFirstTen / runs, greaterThan(7.0));
    });

    test('spaces out songs by the same artist', () {
      // Two artists only, so a naive weighted shuffle interleaves them
      // arbitrarily and frequently produces adjacent pairs.
      final candidates = [
        for (var i = 0; i < 20; i++)
          _candidate('a$i', artist: 'Artist A', album: 'Album A$i'),
        for (var i = 0; i < 20; i++)
          _candidate('b$i', artist: 'Artist B', album: 'Album B$i'),
      ];

      final ordered = orderQueue(candidates, defaults, random: Random(9));

      var adjacentSameArtist = 0;
      for (var i = 1; i < ordered.length; i++) {
        if (ordered[i].artist == ordered[i - 1].artist) adjacentSameArtist++;
      }

      // Perfect alternation is impossible at the tail, but back-to-back pairs
      // should be rare rather than routine.
      expect(adjacentSameArtist, lessThan(8));
    });

    test('untagged artists are not treated as one giant artist run', () {
      final candidates = [
        for (var i = 0; i < 30; i++) _candidate('s$i', artist: '', album: ''),
      ];
      // Must terminate and keep everything despite every artist "matching".
      final ordered = orderQueue(candidates, defaults, random: Random(4));
      expect(ordered.length, 30);
    });

    test('a single-artist library still returns a full queue', () {
      final candidates = [
        for (var i = 0; i < 15; i++)
          _candidate('s$i', artist: 'Only One', album: 'Only Album'),
      ];
      final ordered = orderQueue(candidates, defaults, random: Random(6));
      expect(ordered.length, 15);
    });

    test('disabling the streak breaker turns spacing off', () {
      final weights = ShuffleWeights.forPersonality(
          const ShuffleConfig(streakBreakerEnabled: false));
      expect(weights.artistSpacing, 0);
      expect(weights.albumSpacing, 0);

      final candidates = [
        for (var i = 0; i < 10; i++) _candidate('s$i', artist: 'Same'),
      ];
      expect(orderQueue(candidates, weights, random: Random(2)).length, 10);
    });

    test('the outgoing song seeds artist spacing for the new queue', () {
      final candidates = [
        _candidate('same1', artist: 'Current Artist'),
        _candidate('same2', artist: 'Current Artist'),
        for (var i = 0; i < 10; i++) _candidate('other$i', artist: 'Other $i'),
      ];

      final ordered = orderQueue(
        candidates,
        defaults,
        random: Random(13),
        lastArtist: 'Current Artist',
      );

      expect(ordered.first.artist, isNot('Current Artist'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/song_affinity_service.dart';

/// Fixed reference point so decay maths is deterministic.
final _now = DateTime.utc(2026, 1, 1);

double _daysAgo(int days) =>
    _now.subtract(Duration(days: days)).millisecondsSinceEpoch / 1000.0;

PlayEventRecord _event(String filename, int daysAgo, double ratio) =>
    PlayEventRecord(
      filename: filename,
      timestamp: _daysAgo(daysAgo),
      playRatio: ratio,
    );

/// [count] full listens spread one day apart, starting [startDaysAgo] back.
List<PlayEventRecord> _plays(
  String filename,
  int count, {
  int startDaysAgo = 0,
  double ratio = 1.0,
  int spacingDays = 1,
}) =>
    [
      for (var i = 0; i < count; i++)
        _event(filename, startDaysAgo + i * spacingDays, ratio),
    ];

void main() {
  group('playQuality', () {
    const params = AffinityParams();

    test('a completed listen is full positive evidence', () {
      expect(playQuality(1.0, params), 1.0);
      expect(playQuality(0.85, params), 1.0);
    });

    test('credit ramps linearly between the partial and full thresholds', () {
      // Midpoint of 0.25..0.85 should be half credit.
      expect(playQuality(0.55, params), closeTo(0.5, 0.0001));
    });

    test('an immediate skip is negative evidence, not merely zero', () {
      expect(playQuality(0.02, params), lessThan(0.0));
      expect(playQuality(0.02, params), params.skipPenalty);
    });

    test('a brief abandon is penalized less than an immediate skip', () {
      expect(playQuality(0.15, params), greaterThan(playQuality(0.02, params)));
      expect(playQuality(0.15, params), lessThan(0.0));
    });
  });

  group('decayFactor', () {
    test('halves once per half-life', () {
      expect(decayFactor(90, 90), closeTo(0.5, 0.0001));
      expect(decayFactor(180, 90), closeTo(0.25, 0.0001));
    });

    test('is 1.0 for a play that just happened', () {
      expect(decayFactor(0, 90), 1.0);
    });
  });

  group('percentileOf', () {
    test('resists a single runaway outlier', () {
      // 99 modest values and one enormous one. The p95 reference must stay
      // near the body of the distribution, which is the whole reason we do
      // not normalize against max().
      final values = [for (var i = 0; i < 99; i++) 1.0, 1000.0];
      expect(percentileOf(values, 0.95), lessThan(2.0));
      expect(values.reduce((a, b) => a > b ? a : b), 1000.0);
    });

    test('returns 0 for empty input', () {
      expect(percentileOf([], 0.95), 0.0);
    });
  });

  group('computeAffinities', () {
    test('recent listening outranks stale listening', () {
      // The stale song has far more lifetime plays — the exact case the old
      // count-based weighting got backwards.
      final affinities = computeAffinities(
        events: [
          ..._plays('stale.mp3', 40, startDaysAgo: 200),
          ..._plays('current.mp3', 10, startDaysAgo: 0),
        ],
        now: _now,
      );

      expect(affinities['current.mp3']!.affinity,
          greaterThan(affinities['stale.mp3']!.affinity));
      expect(affinities['stale.mp3']!.playCount,
          greaterThan(affinities['current.mp3']!.playCount));
    });

    test('a habitually skipped song scores below an unplayed one', () {
      final affinities = computeAffinities(
        events: [
          ..._plays('skipped.mp3', 15, ratio: 0.03),
          ..._plays('liked.mp3', 5, ratio: 1.0),
        ],
        now: _now,
      );

      expect(affinities['skipped.mp3']!.affinity, 0.0);
      expect(affinities['skipped.mp3']!.skipRate, greaterThan(0.9));
      expect(affinities['liked.mp3']!.affinity, greaterThan(0.5));
    });

    test('one runaway song does not flatten the rest of the library', () {
      final events = <PlayEventRecord>[
        ..._plays('obsession.mp3', 300, spacingDays: 0),
        for (var i = 0; i < 40; i++) ..._plays('song$i.mp3', 8),
      ];

      final affinities = computeAffinities(events: events, now: _now);

      // Under max-normalization these would all collapse toward zero.
      final ordinary = affinities['song5.mp3']!.affinity;
      expect(ordinary, greaterThan(0.3));
      expect(affinities['obsession.mp3']!.affinity, 1.0);
    });

    test('favorites get a floor even with no play history at all', () {
      final affinities = computeAffinities(
        events: const [],
        now: _now,
        favorites: {'never-played.mp3'},
      );

      expect(affinities['never-played.mp3']!.affinity,
          const AffinityParams().favoriteFloor);
      expect(affinities['never-played.mp3']!.playCount, 0);
    });

    test('a favorite the listener skips keeps the floor, not the skip score',
        () {
      final affinities = computeAffinities(
        events: _plays('fav.mp3', 10, ratio: 0.02),
        now: _now,
        favorites: {'fav.mp3'},
      );

      expect(affinities['fav.mp3']!.affinity,
          const AffinityParams().favoriteFloor);
    });

    test('burnout registers for a song hammered in the last few days', () {
      final affinities = computeAffinities(
        events: [
          ..._plays('binge.mp3', 20, spacingDays: 0),
          ..._plays('steady.mp3', 20, spacingDays: 14),
        ],
        now: _now,
      );

      expect(affinities['binge.mp3']!.recentSaturation, greaterThan(1.0));
      expect(affinities['steady.mp3']!.recentSaturation,
          lessThan(affinities['binge.mp3']!.recentSaturation));
    });

    test('completion rate reflects how much of the song is actually heard', () {
      final affinities = computeAffinities(
        events: [
          ..._plays('full.mp3', 5, ratio: 1.0),
          ..._plays('half.mp3', 5, ratio: 0.5),
        ],
        now: _now,
      );

      expect(affinities['full.mp3']!.completionRate, closeTo(1.0, 0.01));
      expect(affinities['half.mp3']!.completionRate, closeTo(0.5, 0.01));
    });

    test('future-dated events do not blow up decay', () {
      // Clock skew and imported libraries can produce these.
      final affinities = computeAffinities(
        events: [_event('skewed.mp3', -30, 1.0)],
        now: _now,
      );

      expect(affinities['skewed.mp3']!.affinity, isNot(isNaN));
      expect(affinities['skewed.mp3']!.affinity, lessThanOrEqualTo(1.0));
    });

    test('songs never played are simply absent', () {
      final affinities = computeAffinities(
        events: _plays('played.mp3', 3),
        now: _now,
      );

      expect(affinities.containsKey('unplayed.mp3'), isFalse);
      expect(SongAffinity.unknown.affinity, 0.0);
      expect(SongAffinity.unknown.hasHistory, isFalse);
    });
  });
}

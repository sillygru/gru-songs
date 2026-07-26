/// Turns raw play events into a per-song taste score.
///
/// This is the "what does the listener actually like" half of shuffle; picking
/// and ordering songs from those scores lives in `shuffle_selector.dart`.
///
/// The model is deliberately evidence-based rather than count-based. A play
/// event is not a vote of equal weight: finishing a song is strong positive
/// evidence, abandoning it ten seconds in is *negative* evidence, and evidence
/// from a year ago says less about today's taste than evidence from last week.
/// Raw lifetime play counts collapse all three distinctions.
///
/// Pure by design — no I/O, no clock reads beyond the injected [now] — so the
/// whole model is directly testable.
library;

import 'dart:math';

/// One play event, as stored in the `playevent` table.
class PlayEventRecord {
  /// Primary key for all user data (see CLAUDE.md).
  final String filename;

  /// Epoch seconds, matching the `playevent.timestamp` column.
  final double timestamp;

  /// Fraction of the song actually heard, 0..1.
  final double playRatio;

  const PlayEventRecord({
    required this.filename,
    required this.timestamp,
    required this.playRatio,
  });
}

/// Per-song output of [computeAffinities].
class SongAffinity {
  /// Normalized taste score, 0..1. Comparable across the library.
  final double affinity;

  /// Short-term over-exposure, 0..1+. High when a song has been played a lot
  /// in the last few days. Used to damp today's obsession, never to bury it.
  final double recentSaturation;

  /// Recency-weighted average fraction of the song heard, 0..1.
  final double completionRate;

  /// Recency-weighted fraction of plays abandoned early, 0..1.
  final double skipRate;

  /// Number of events considered (all of them, undecayed).
  final int playCount;

  /// Epoch seconds of the most recent event, or null if never played.
  final double? lastPlayedAt;

  const SongAffinity({
    required this.affinity,
    required this.recentSaturation,
    required this.completionRate,
    required this.skipRate,
    required this.playCount,
    required this.lastPlayedAt,
  });

  /// A song with no listening history at all.
  static const unknown = SongAffinity(
    affinity: 0.0,
    recentSaturation: 0.0,
    completionRate: 0.0,
    skipRate: 0.0,
    playCount: 0,
    lastPlayedAt: null,
  );

  bool get hasHistory => playCount > 0;
}

/// Tunables for [computeAffinities]. Defaults are the shipping values; tests
/// override them to isolate one behaviour at a time.
class AffinityParams {
  /// Days for a play's contribution to lose half its weight.
  final double halfLifeDays;

  /// Days for the short-term saturation signal to halve. Much shorter than
  /// [halfLifeDays] — this tracks "on repeat this week", not taste.
  final double saturationHalfLifeDays;

  /// Decayed play count treated as "saturated". At this level a song's score is
  /// halved by [SongAffinity.recentSaturation] damping downstream.
  final double saturationTarget;

  /// At or above this ratio a play counts as a full, deliberate listen.
  final double fullListenRatio;

  /// Below this ratio a play counts as an outright skip (negative evidence).
  final double skipRatio;

  /// Ratio under which a play carries no positive credit at all.
  final double partialRatio;

  /// Evidence value of a completed listen.
  final double fullListenCredit;

  /// Evidence value (negative) of an immediate skip.
  final double skipPenalty;

  /// Evidence value (negative) of a brief but not-immediate abandon.
  final double partialPenalty;

  /// Percentile of the raw score distribution mapped to affinity 1.0. Using a
  /// high percentile rather than the maximum keeps one runaway song from
  /// flattening everything else into near-zero.
  final double normalizationPercentile;

  /// Affinity floor for songs the user explicitly favorited. Expresses intent
  /// directly, so a favorite ranks even with no play history behind it.
  final double favoriteFloor;

  const AffinityParams({
    this.halfLifeDays = 90.0,
    this.saturationHalfLifeDays = 2.0,
    this.saturationTarget = 6.0,
    this.fullListenRatio = 0.85,
    this.skipRatio = 0.10,
    this.partialRatio = 0.25,
    this.fullListenCredit = 1.0,
    this.skipPenalty = -0.6,
    this.partialPenalty = -0.2,
    this.normalizationPercentile = 0.95,
    this.favoriteFloor = 0.6,
  });
}

/// Evidence value of a single play, from how much of the song was heard.
///
/// Finishing is worth [AffinityParams.fullListenCredit]; between the partial
/// and full thresholds credit ramps linearly from 0; below that the play is
/// evidence *against* the song, most strongly when abandoned immediately.
double playQuality(double playRatio, AffinityParams params) {
  if (playRatio >= params.fullListenRatio) return params.fullListenCredit;
  if (playRatio >= params.partialRatio) {
    final span = params.fullListenRatio - params.partialRatio;
    if (span <= 0) return params.fullListenCredit;
    final t = (playRatio - params.partialRatio) / span;
    return t * params.fullListenCredit;
  }
  if (playRatio >= params.skipRatio) return params.partialPenalty;
  return params.skipPenalty;
}

/// Exponential decay factor for an event [ageDays] old.
double decayFactor(double ageDays, double halfLifeDays) {
  if (halfLifeDays <= 0) return 1.0;
  if (ageDays <= 0) return 1.0;
  return pow(0.5, ageDays / halfLifeDays).toDouble();
}

/// Value at [percentile] (0..1) of [values], which need not be sorted.
///
/// Returns 0 for an empty input. Interpolates between neighbours so small
/// libraries don't quantize hard onto a single sample.
double percentileOf(List<double> values, double percentile) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  if (sorted.length == 1) return sorted.first;
  final rank = (percentile.clamp(0.0, 1.0)) * (sorted.length - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower];
  final t = rank - lower;
  return sorted[lower] * (1 - t) + sorted[upper] * t;
}

/// Builds the affinity map for every song appearing in [events], plus every
/// song in [favorites] (which get the favorite floor even with no history).
///
/// [now] is injected rather than read so decay is deterministic under test.
Map<String, SongAffinity> computeAffinities({
  required List<PlayEventRecord> events,
  required DateTime now,
  Set<String> favorites = const {},
  AffinityParams params = const AffinityParams(),
}) {
  final nowSeconds = now.millisecondsSinceEpoch / 1000.0;

  final rawScore = <String, double>{};
  final weightedCompletion = <String, double>{};
  final weightedSkips = <String, double>{};
  final decayWeightTotal = <String, double>{};
  final saturation = <String, double>{};
  final counts = <String, int>{};
  final lastPlayed = <String, double>{};

  for (final event in events) {
    final ageDays = (nowSeconds - event.timestamp) / 86400.0;
    // Clock skew or imported data can put events slightly in the future;
    // treat them as "now" rather than letting decay explode above 1.
    final safeAgeDays = ageDays < 0 ? 0.0 : ageDays;

    final decay = decayFactor(safeAgeDays, params.halfLifeDays);
    final ratio = event.playRatio.clamp(0.0, 1.0);
    final key = event.filename;

    rawScore.update(
      key,
      (v) => v + playQuality(ratio, params) * decay,
      ifAbsent: () => playQuality(ratio, params) * decay,
    );

    weightedCompletion.update(key, (v) => v + ratio * decay,
        ifAbsent: () => ratio * decay);
    decayWeightTotal.update(key, (v) => v + decay, ifAbsent: () => decay);

    if (ratio < params.skipRatio) {
      weightedSkips.update(key, (v) => v + decay, ifAbsent: () => decay);
    }

    saturation.update(
      key,
      (v) => v + decayFactor(safeAgeDays, params.saturationHalfLifeDays),
      ifAbsent: () => decayFactor(safeAgeDays, params.saturationHalfLifeDays),
    );

    counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    lastPlayed.update(key, (v) => max(v, event.timestamp),
        ifAbsent: () => event.timestamp);
  }

  // Normalize against a high percentile of the *positive* scores. Negative
  // scores (songs the user keeps skipping) must not drag the reference down.
  final positiveScores =
      rawScore.values.where((v) => v > 0).toList(growable: false);
  final reference =
      percentileOf(positiveScores, params.normalizationPercentile);

  final result = <String, SongAffinity>{};

  for (final entry in rawScore.entries) {
    final key = entry.key;
    final weightTotal = decayWeightTotal[key] ?? 0.0;

    double affinity;
    if (reference > 0) {
      affinity = (entry.value / reference).clamp(0.0, 1.0);
    } else {
      affinity = entry.value > 0 ? 1.0 : 0.0;
    }

    if (favorites.contains(key)) {
      affinity = max(affinity, params.favoriteFloor);
    }

    result[key] = SongAffinity(
      affinity: affinity,
      recentSaturation: params.saturationTarget > 0 && saturation[key] != null
          ? saturation[key]! / params.saturationTarget
          : 0.0,
      completionRate: weightTotal > 0
          ? (weightedCompletion[key] ?? 0.0) / weightTotal
          : 0.0,
      skipRate:
          weightTotal > 0 ? (weightedSkips[key] ?? 0.0) / weightTotal : 0.0,
      playCount: counts[key] ?? 0,
      lastPlayedAt: lastPlayed[key],
    );
  }

  // Favorites the listener never got around to playing still carry intent.
  for (final favorite in favorites) {
    result.putIfAbsent(
      favorite,
      () => SongAffinity(
        affinity: params.favoriteFloor,
        recentSaturation: 0.0,
        completionRate: 0.0,
        skipRate: 0.0,
        playCount: 0,
        lastPlayedAt: null,
      ),
    );
  }

  return result;
}

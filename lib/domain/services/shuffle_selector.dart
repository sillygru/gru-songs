/// Picks and orders songs for shuffle from the taste scores produced by
/// `song_affinity_service.dart`.
///
/// Two ideas shape this file:
///
/// 1. **Personality is data, not control flow.** Every personality resolves to
///    a [ShuffleWeights] before any scoring happens, so the scoring maths is
///    written once. Adding a personality means adding a constructor, not
///    threading another `if` through the weight function.
///
/// 2. **Selecting and ordering are the same maths.** The song that plays first
///    is drawn from the same distribution as the rest of the queue, so the
///    listener's taste governs the track they actually hear.
///
/// Pure — the only randomness is the injected [Random].
library;

import 'dart:math';

import '../../models/shuffle_config.dart';
import 'song_affinity_service.dart';

/// A song (or a merged group of songs, from the caller's perspective) that
/// shuffle may choose. Generic over [T] so the caller keeps its own payload
/// type — `AudioPlayerManager` passes its merge-group wrapper through.
class ShuffleCandidate<T> {
  final T payload;
  final String artist;
  final String album;
  final SongAffinity affinity;
  final bool isFavorite;
  final bool isSuggestLess;
  final bool isInPlaylist;

  /// Position in recent play history — 0 is the most recently played song.
  /// Null when the song isn't in the history window at all.
  final int? historyIndex;

  const ShuffleCandidate({
    required this.payload,
    required this.artist,
    required this.album,
    required this.affinity,
    this.isFavorite = false,
    this.isSuggestLess = false,
    this.isInPlaylist = false,
    this.historyIndex,
  });
}

/// Resolved, personality-independent knobs the scoring maths reads.
class ShuffleWeights {
  /// Exponent applied to affinity. Above 1 sharpens toward favourites, below 1
  /// flattens the field toward uniform.
  final double affinityExponent;

  /// Additive lift for songs with little or no history. Additive rather than
  /// multiplicative so unheard songs stay reachable even at high
  /// [affinityExponent], where their multiplicative score rounds to nothing.
  final double noveltyBoost;

  /// How hard to push down songs played recently, 0..1.
  final double repeatAversion;

  /// How hard to push down songs the listener habitually abandons, 0..1.
  final double skipAversion;

  /// How hard short-term over-exposure damps a song, 0..1+.
  final double burnoutDamping;

  /// Preferred minimum gap, in queue slots, between songs sharing an artist.
  final int artistSpacing;

  /// Preferred minimum gap, in queue slots, between songs sharing an album.
  final int albumSpacing;

  final double favoriteBoost;
  final double suggestLessPenalty;
  final double playlistBoost;

  /// Number of recent-history slots anti-repeat spans.
  final int historyLimit;

  const ShuffleWeights({
    required this.affinityExponent,
    required this.noveltyBoost,
    required this.repeatAversion,
    required this.skipAversion,
    required this.burnoutDamping,
    required this.artistSpacing,
    required this.albumSpacing,
    required this.favoriteBoost,
    required this.suggestLessPenalty,
    required this.playlistBoost,
    required this.historyLimit,
  });

  /// Resolves a [ShuffleConfig] — personality plus every user-facing setting —
  /// into scoring knobs.
  ///
  /// Every field of [ShuffleConfig] is consumed here or by the caller. If a
  /// setting is exposed in the UI it must have an effect on this struct.
  factory ShuffleWeights.forPersonality(ShuffleConfig config) {
    final antiRepeat = config.antiRepeatEnabled;
    final streak = config.streakBreakerEnabled;

    // Shared explicit-signal handling. `favoriteMultiplier` and
    // `suggestLessMultiplier` apply in every personality, not just custom.
    final baseFavorite = config.favoriteMultiplier;
    final baseSuggestLess = config.suggestLessMultiplier;

    switch (config.personality) {
      case ShufflePersonality.consistent:
        return ShuffleWeights(
          affinityExponent: 2.0,
          noveltyBoost: 0.05,
          repeatAversion: antiRepeat ? 0.55 : 0.0,
          skipAversion: 0.5,
          burnoutDamping: 0.5,
          artistSpacing: streak ? 3 : 0,
          albumSpacing: streak ? 2 : 0,
          favoriteBoost: max(baseFavorite, 1.4),
          suggestLessPenalty: baseSuggestLess,
          playlistBoost: 1.0,
          historyLimit: config.historyLimit,
        );

      case ShufflePersonality.explorer:
        return ShuffleWeights(
          affinityExponent: 0.4,
          noveltyBoost: 1.0,
          repeatAversion: antiRepeat ? 0.95 : 0.0,
          skipAversion: 0.35,
          burnoutDamping: 1.5,
          artistSpacing: streak ? 8 : 0,
          albumSpacing: streak ? 6 : 0,
          favoriteBoost: min(baseFavorite, 1.12),
          suggestLessPenalty: baseSuggestLess,
          playlistBoost: 1.0,
          historyLimit: config.historyLimit,
        );

      case ShufflePersonality.custom:
        return _customWeights(config);

      case ShufflePersonality.defaultMode:
        return ShuffleWeights(
          affinityExponent: 1.2,
          noveltyBoost: 0.25,
          repeatAversion: antiRepeat ? 0.8 : 0.0,
          skipAversion: 0.45,
          burnoutDamping: 1.0,
          artistSpacing: streak ? 5 : 0,
          albumSpacing: streak ? 4 : 0,
          favoriteBoost: baseFavorite,
          suggestLessPenalty: baseSuggestLess,
          playlistBoost: 1.0,
          historyLimit: config.historyLimit,
        );
    }
  }

  static ShuffleWeights _customWeights(ShuffleConfig config) {
    // The two play-count sliders oppose each other; their difference is the
    // single "familiar vs unfamiliar" axis. `favorLeastPlayed` breaks the tie
    // when the listener never touched the advanced sliders.
    var net = (config.mostPlayedWeight - config.leastPlayedWeight) / 100.0;
    if (config.mostPlayedWeight == 0 && config.leastPlayedWeight == 0) {
      net = config.favorLeastPlayed ? -0.35 : 0.35;
    }

    final double affinityExponent =
        net >= 0 ? 1.0 + net * 1.5 : 1.0 / (1.0 + net.abs() * 1.5);

    return ShuffleWeights(
      affinityExponent: affinityExponent,
      noveltyBoost: max(0.0, -net) * 1.2,
      repeatAversion:
          config.antiRepeatEnabled && config.avoidRepeatingSongs ? 0.85 : 0.0,
      skipAversion: 0.45,
      burnoutDamping: 1.0,
      artistSpacing: config.avoidRepeatingArtists ? 5 : 0,
      albumSpacing: config.avoidRepeatingAlbums ? 4 : 0,
      // A slider left at 0 means "no opinion", which must fall back to the
      // standard multiplier rather than silently ignoring favorites — the
      // latter is what made custom mode feel like it disregarded taste.
      favoriteBoost: config.favoritesWeight == 0
          ? config.favoriteMultiplier
          : 1.0 + config.favoritesWeight / 100.0,
      suggestLessPenalty: config.suggestLessWeight == 0
          ? config.suggestLessMultiplier
          : (1.0 - config.suggestLessWeight / 100.0).clamp(0.0, 2.0),
      // Playlist membership genuinely has no baseline preference, so 0 here
      // really does mean neutral.
      playlistBoost: 1.0 + config.playlistSongsWeight / 100.0,
      historyLimit: config.historyLimit,
    );
  }
}

/// Score floor. Nothing in the library is ever truly unreachable — a listener
/// who waits long enough should eventually hear any song they own.
const double _minScore = 0.0001;

/// Weight of a single candidate under [weights]. Deterministic.
double scoreCandidate<T>(
    ShuffleCandidate<T> candidate, ShuffleWeights weights) {
  final affinity = candidate.affinity;
  final a = affinity.affinity.clamp(0.0, 1.0);

  // Familiarity: sharpened or flattened by the personality's exponent.
  double score = pow(a, weights.affinityExponent).toDouble();

  // Discovery: decays smoothly with play count rather than switching off after
  // the first listen, so a song heard once is still somewhat "new".
  final novelty = 1.0 / (1.0 + affinity.playCount);
  score += weights.noveltyBoost * novelty;

  // Songs the listener habitually abandons.
  score *= (1.0 - affinity.skipRate * weights.skipAversion).clamp(0.05, 1.0);

  // Short-term over-exposure. Damps this week's obsession without burying it.
  score /= (1.0 + affinity.recentSaturation * weights.burnoutDamping);

  // Anti-repeat: strongest for the song just played, fading to nothing at the
  // edge of the history window. Replaces a hardcoded bucket ladder that didn't
  // scale with the configured history limit.
  final historyIndex = candidate.historyIndex;
  if (weights.repeatAversion > 0 &&
      historyIndex != null &&
      weights.historyLimit > 0 &&
      historyIndex < weights.historyLimit) {
    final proximity = 1.0 - (historyIndex / weights.historyLimit);
    final penalty = (weights.repeatAversion * proximity).clamp(0.0, 0.98);
    score *= (1.0 - penalty);
  }

  // Explicit user intent last, so it multiplies the finished picture.
  if (candidate.isFavorite) score *= weights.favoriteBoost;
  if (candidate.isSuggestLess) score *= weights.suggestLessPenalty;
  if (candidate.isInPlaylist) score *= weights.playlistBoost;

  if (score.isNaN || score <= 0) return _minScore;
  return max(score, _minScore);
}

/// Scores every candidate once.
List<double> scoreCandidates<T>(
  List<ShuffleCandidate<T>> candidates,
  ShuffleWeights weights,
) =>
    [for (final c in candidates) scoreCandidate(c, weights)];

/// Draws one candidate proportional to its score.
///
/// This is what the shuffle button uses for the first track. Previously that
/// song was drawn with a plain uniform `nextInt`, which is why no personality
/// or weight setting could influence what the listener actually heard.
ShuffleCandidate<T>? selectSeed<T>(
  List<ShuffleCandidate<T>> candidates,
  ShuffleWeights weights, {
  Random? random,
}) {
  if (candidates.isEmpty) return null;
  final rng = random ?? Random();
  final scores = scoreCandidates(candidates, weights);
  final index = _sampleIndex(scores, rng);
  return candidates[index];
}

int _sampleIndex(List<double> scores, Random rng) {
  final total = scores.fold(0.0, (a, b) => a + b);
  if (total <= 0) return rng.nextInt(scores.length);

  final target = rng.nextDouble() * total;
  var cumulative = 0.0;
  for (var i = 0; i < scores.length; i++) {
    cumulative += scores[i];
    if (target <= cumulative) return i;
  }
  return scores.length - 1;
}

/// Orders every candidate into a full queue.
///
/// Two stages:
///
/// 1. A weighted permutation via the exponential race (Efraimidis–Spirakis):
///    drawing `-ln(U)/w` per candidate and sorting ascending is equivalent to
///    repeated weighted sampling without replacement, but runs in O(n log n)
///    instead of the O(n²) rescan the previous implementation did.
/// 2. A spacing repair pass that pulls apart runs of the same artist or album.
///    Looking back over a window is what actually spreads a discography out;
///    comparing only against the immediately previous track — as the old
///    streak breaker did — still permits A B A B A.
///
/// [lastArtist] / [lastAlbum] seed the look-back with the currently playing
/// song so the join between it and the new queue is spaced too.
List<ShuffleCandidate<T>> orderQueue<T>(
  List<ShuffleCandidate<T>> candidates,
  ShuffleWeights weights, {
  Random? random,
  String? lastArtist,
  String? lastAlbum,
}) {
  if (candidates.length <= 1) return List.of(candidates);
  final rng = random ?? Random();

  final scores = scoreCandidates(candidates, weights);

  final keyed = <({double key, ShuffleCandidate<T> candidate})>[];
  for (var i = 0; i < candidates.length; i++) {
    final w = max(scores[i], _minScore);
    // nextDouble() can return exactly 0; nudge so log() stays finite.
    final u = max(rng.nextDouble(), 1e-12);
    keyed.add((key: -log(u) / w, candidate: candidates[i]));
  }
  keyed.sort((a, b) => a.key.compareTo(b.key));

  final ordered = [for (final k in keyed) k.candidate];
  return _applySpacing(ordered, weights, lastArtist, lastAlbum);
}

/// Normalizes an artist/album string for comparison. Empty means "unknown".
String _norm(String value) => value.toLowerCase().trim();

/// Pulls same-artist / same-album songs apart by promoting, from a bounded
/// look-ahead window, whichever upcoming track is furthest from its last
/// appearance.
///
/// Spacing is best-effort rather than all-or-nothing. A library with only a
/// handful of artists can't satisfy a five-slot gap at all, and an algorithm
/// that demands perfection simply gives up there and leaves the clumps in
/// place — so the case that most needs spreading out gets none. Ranking by
/// "how badly does this clash" instead degrades gracefully: it still finds the
/// alternating order when a perfect one doesn't exist.
List<ShuffleCandidate<T>> _applySpacing<T>(
  List<ShuffleCandidate<T>> ordered,
  ShuffleWeights weights,
  String? lastArtist,
  String? lastAlbum,
) {
  final artistSpacing = weights.artistSpacing;
  final albumSpacing = weights.albumSpacing;
  if (artistSpacing <= 0 && albumSpacing <= 0) return ordered;

  const lookAhead = 25;
  final result = List<ShuffleCandidate<T>>.of(ordered);

  // Last placed position per artist/album. Seeded with the outgoing song at a
  // negative index so spacing is measured from before the queue starts.
  final lastArtistAt = <String, int>{};
  final lastAlbumAt = <String, int>{};
  if (lastArtist != null && _norm(lastArtist).isNotEmpty) {
    lastArtistAt[_norm(lastArtist)] = -1;
  }
  if (lastAlbum != null && _norm(lastAlbum).isNotEmpty) {
    lastAlbumAt[_norm(lastAlbum)] = -1;
  }

  /// How far this candidate falls short of the desired gaps at [position].
  /// Zero means it fits cleanly; larger means a tighter clash. Untagged
  /// artists and albums never clash — otherwise every untagged song in the
  /// library would look like one enormous artist run.
  int deficit(ShuffleCandidate<T> candidate, int position) {
    var total = 0;

    final artist = _norm(candidate.artist);
    if (artistSpacing > 0 && artist.isNotEmpty) {
      final at = lastArtistAt[artist];
      if (at != null) total += max(0, artistSpacing - (position - at));
    }

    final album = _norm(candidate.album);
    if (albumSpacing > 0 && album.isNotEmpty) {
      final at = lastAlbumAt[album];
      if (at != null) total += max(0, albumSpacing - (position - at));
    }

    return total;
  }

  for (var i = 0; i < result.length; i++) {
    if (deficit(result[i], i) > 0) {
      // Promote the least-clashing track from the window. Ties keep the
      // earliest index, preserving the weighted order this started from.
      final limit = min(result.length, i + 1 + lookAhead);
      var bestIndex = i;
      var bestDeficit = deficit(result[i], i);

      for (var j = i + 1; j < limit && bestDeficit > 0; j++) {
        final candidateDeficit = deficit(result[j], i);
        if (candidateDeficit < bestDeficit) {
          bestDeficit = candidateDeficit;
          bestIndex = j;
        }
      }

      if (bestIndex != i) {
        result.insert(i, result.removeAt(bestIndex));
      }
    }

    final placed = result[i];
    final artist = _norm(placed.artist);
    final album = _norm(placed.album);
    if (artist.isNotEmpty) lastArtistAt[artist] = i;
    if (album.isNotEmpty) lastAlbumAt[album] = i;
  }

  return result;
}

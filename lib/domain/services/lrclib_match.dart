import '../../models/song.dart';
import '../models/lrclib_result.dart';

/// Ranks LRCLIB candidates against the local file. Pure — no I/O — so the
/// scoring can be tested directly without touching the network.
///
/// LRCLIB search is generous: a query for one track routinely returns twenty
/// records spread across compilations, live cuts and mislabelled uploads. The
/// duration of the local file is the strongest signal available for telling
/// them apart, so it dominates the score; title and artist agreement break the
/// remaining ties, and a synced record edges out an otherwise equal plain one
/// because that is what the player can actually animate.

/// Beyond this the record is almost certainly a different recording.
const Duration _durationCutoff = Duration(seconds: 15);

/// Inside this, the difference is rounding or a trailing silence trim.
const Duration _durationExact = Duration(seconds: 2);

/// Sorts [results] best-first, dropping any that cannot supply lyrics.
///
/// Stable with respect to the incoming order, so an exact `/api/get` hit placed
/// first stays ahead of an equally-scoring search result.
List<LrclibResult> rankLrclibResults(List<LrclibResult> results, Song song) {
  final usable = results.where((r) => r.isUsable).toList();

  final scored = <({LrclibResult result, double score, int index})>[
    for (var i = 0; i < usable.length; i++)
      (result: usable[i], score: scoreLrclibResult(usable[i], song), index: i),
  ];

  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });

  return [for (final entry in scored) entry.result];
}

/// Higher is better. Roughly 0–100, but only the ordering is meaningful.
double scoreLrclibResult(LrclibResult result, Song song) {
  var score = 0.0;

  final local = song.duration;
  final remote = result.duration;
  if (local != null && remote != null) {
    final delta = (local - remote).abs();
    if (delta <= _durationExact) {
      score += 50;
    } else if (delta >= _durationCutoff) {
      // Not disqualified outright — a wrongly-tagged local duration should not
      // hide the only lyrics available — but pushed well down the list.
      score -= 25;
    } else {
      // Linear falloff between the two thresholds.
      final span = (_durationCutoff - _durationExact).inMilliseconds;
      final over = (delta - _durationExact).inMilliseconds;
      score += 50 * (1 - over / span);
    }
  }

  if (_normalize(result.trackName) == _normalize(song.title)) {
    score += 25;
  } else if (_containsEither(result.trackName, song.title)) {
    score += 10;
  }

  if (_normalize(result.artistName) == _normalize(song.artist)) {
    score += 20;
  } else if (_containsEither(result.artistName, song.artist)) {
    score += 8;
  }

  if (_normalize(result.albumName) == _normalize(song.album)) {
    score += 8;
  }

  if (result.hasSynced) score += 12;

  // An instrumental record is a legitimate answer but a poor guess when the
  // user went looking for words, so it never outranks a real lyric sheet.
  if (result.instrumental) score -= 15;

  return score;
}

/// Casefolds, strips accents-free punctuation and collapses whitespace, so
/// "Don't Stop Me Now!" and "dont stop me now" compare equal.
String _normalize(String value) {
  final lowered = value.toLowerCase();
  final stripped = lowered.replaceAll(RegExp(r"[^\w\s]", unicode: true), ' ');
  return stripped.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool _containsEither(String a, String b) {
  final na = _normalize(a);
  final nb = _normalize(b);
  if (na.isEmpty || nb.isEmpty) return false;
  return na.contains(nb) || nb.contains(na);
}

/// Cleans up a local file's title before it becomes an LRCLIB query. Pure — no
/// I/O — so it can be tested directly.
///
/// Files ripped from video sites arrive tagged like
/// "Artist - Title (Official Audio)". LRCLIB's `track_name` is a filter, so the
/// descriptor suffix and the leading "Artist -" prefix make the search miss
/// even when the lyrics are right there. Stripping them is deliberately
/// conservative: only bracketed groups that carry a known noise word are
/// dropped (so "(Remix)" or "(Acoustic)" — which pick out a distinct recording
/// — survive), and the leading prefix is removed only when it actually matches
/// the file's own artist tag.
library;

/// Words that mark a bracketed group as a descriptor rather than part of the
/// song name. Matched as substrings, lower-cased, so "lyric" covers "Lyrics"
/// and "Lyric Video".
const _noiseWords = <String>{
  'official',
  'audio',
  'video',
  'lyric',
  'visualizer',
  'visualiser',
  'explicit',
  'remaster',
  'hd',
  'hq',
  '4k',
  'mv',
  'prod',
};

final _bracketGroup = RegExp(r'[\(\[]([^\)\]]*)[\)\]]');
final _artistPrefix = RegExp(r'^(.*?)\s*[-–—:|]\s*(.+)$');
final _edgeSeparators = RegExp(r'^[-–—:|\s]+|[-–—:|\s]+$');

/// Returns [title] with descriptor brackets and a matching "Artist -" prefix
/// removed. Falls back to the original when cleaning would leave nothing.
String cleanSearchTitle(String title, {String? artist}) {
  var result = title.replaceAllMapped(_bracketGroup, (match) {
    final inner = match.group(1)!.toLowerCase();
    return _noiseWords.any(inner.contains) ? '' : match.group(0)!;
  });

  final a = artist?.trim() ?? '';
  if (a.isNotEmpty) {
    final match = _artistPrefix.firstMatch(result);
    if (match != null && _normalize(match.group(1)!) == _normalize(a)) {
      result = match.group(2)!;
    }
  }

  final cleaned = _collapse(result);
  return cleaned.isEmpty ? title.trim() : cleaned;
}

/// Collapses whitespace and trims stray leading/trailing separators left behind
/// once a bracket or prefix is removed.
String _collapse(String value) {
  final spaced = value.replaceAll(RegExp(r'\s+'), ' ');
  return spaced.replaceAll(_edgeSeparators, '');
}

/// Casefold + strip punctuation + collapse whitespace, so a prefix compares
/// equal to the artist tag regardless of styling.
String _normalize(String value) {
  final lowered = value.toLowerCase();
  final stripped = lowered.replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ');
  return stripped.trim().replaceAll(RegExp(r'\s+'), ' ');
}

import 'package:path/path.dart' as p;

/// Filename is the primary key for all user data (favorites, stats,
/// playlists, merges). Paths vary across devices; filename does not.
///
/// Normalized form: basename, trimmed, lowercased.
/// This is the sole place defining that rule.
class Filename {
  final String value;
  const Filename(this.value);

  /// Basename without directories (not lowercased).
  String get basename => p.basename(value);

  /// Normalized key used for equality and map lookups.
  // ignore: unintended_html_in_doc_comment
  String get normalized => _normalize(value);

  static String normalize(String raw) => _normalize(raw);

  static String _normalize(String raw) {
    var name = raw.trim();
    if (name.isEmpty) return '';
    name = p.basename(name);
    return name.toLowerCase();
  }

  /// Extract filename from a file url/path and normalize it.
  static String fromUrl(String url) => _normalize(url);

  @override
  bool operator ==(Object other) =>
      other is Filename && normalized == other.normalized;

  @override
  int get hashCode => normalized.hashCode;

  @override
  String toString() => 'Filename($value)';
}

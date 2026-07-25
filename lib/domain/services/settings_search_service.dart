import '../models/settings_entry.dart';

/// Prefix search over the settings registry.
///
/// Pure and generic over [SettingsEntry] subclasses so the presentation layer
/// can carry icons and screen builders on its own entry type without this
/// having to know about widgets.
class SettingsSearchService {
  const SettingsSearchService();

  static const int maxResults = 30;

  /// Every whitespace-separated token in [query] must match somewhere, so
  /// typing more words narrows rather than widens. A token matches when it is
  /// a prefix of any word in the title, subtitle, breadcrumb or keywords.
  ///
  /// Ranking, best first: a token starting the title, a token starting any
  /// later word of the title, a subtitle hit, then a keyword or breadcrumb
  /// hit. Ties keep registry order, which is the order of the settings pages
  /// themselves.
  List<T> search<T extends SettingsEntry>(List<T> entries, String query) {
    final tokens = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (tokens.isEmpty) return const [];

    final scored = <(int, int, T)>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final title = entry.title.toLowerCase();
      final subtitle = entry.subtitle?.toLowerCase() ?? '';
      final breadcrumb = entry.breadcrumb.toLowerCase();
      final keywords = entry.keywords.map((k) => k.toLowerCase()).toList();

      var total = 0;
      var matchedAll = true;

      for (final token in tokens) {
        final score = _tokenScore(token, title, subtitle, breadcrumb, keywords);
        if (score == 0) {
          matchedAll = false;
          break;
        }
        total += score;
      }

      if (matchedAll) scored.add((-total, i, entry));
    }

    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });

    return [for (final s in scored.take(maxResults)) s.$3];
  }

  int _tokenScore(
    String token,
    String title,
    String subtitle,
    String breadcrumb,
    List<String> keywords,
  ) {
    if (title.startsWith(token)) return 8;
    if (_hasWordPrefix(title, token)) return 6;
    if (_hasWordPrefix(subtitle, token)) return 3;
    if (keywords.any((k) => k.startsWith(token))) return 2;
    if (_hasWordPrefix(breadcrumb, token)) return 1;
    return 0;
  }

  /// Prefix match on any word, so "fade" finds "Auto Fade" but "ade" doesn't.
  bool _hasWordPrefix(String haystack, String token) {
    if (haystack.isEmpty) return false;
    for (final word in haystack.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.startsWith(token)) return true;
    }
    return false;
  }
}

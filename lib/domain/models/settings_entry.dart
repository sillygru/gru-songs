/// One searchable setting.
///
/// Pure text only — the icon and the screen it opens live on the presentation
/// subclass in `settings_registry.dart`, so the search itself stays testable
/// without a widget tree.
class SettingsEntry {
  /// Matches the row's `searchId`, so the owning page can scroll to it and
  /// pulse it. Null for entries that *are* a page rather than a row on one.
  final String? anchorId;

  /// The row's label, verbatim.
  final String title;

  final String? subtitle;

  /// Where it lives, e.g. `Playback › Transitions`. Shown under the result.
  final String breadcrumb;

  /// Words a person might search for that don't appear in the title —
  /// 'gapless' for Crossfade, 'dark mode' for Theme.
  final List<String> keywords;

  const SettingsEntry({
    required this.title,
    required this.breadcrumb,
    this.anchorId,
    this.subtitle,
    this.keywords = const [],
  });

  /// Unique within the registry.
  String get key => anchorId ?? '$breadcrumb/$title';
}

import '../../models/song.dart';

/// A suggested group of songs that share similar titles/metadata and may be merged.
class MergeCandidateGroup {
  final String title;
  final List<Song> songs;

  const MergeCandidateGroup({
    required this.title,
    required this.songs,
  });
}

/// Domain service that scans the library for potential songs to merge based on
/// title and artist similarity (e.g. remixes, live versions, acoustics).
class SongMergeFinder {
  const SongMergeFinder._();

  static List<MergeCandidateGroup> findCandidates(
    List<Song> songs,
    Map<String, List<String>> existingMergedGroups,
  ) {
    if (songs.length < 2) return [];

    // Map existing merged groups to sets for fast lookup
    final existingGroupSets = existingMergedGroups.values
        .map((filenames) => filenames.toSet())
        .toList();

    final Map<String, List<Song>> candidateMap = {};
    final Map<String, String> displayTitleMap = {};

    for (final song in songs) {
      final cleanedTitle = _cleanTitle(song.title);
      final cleanedArtist = _cleanArtist(song.artist);

      if (cleanedTitle.isEmpty) continue;

      // Group key combining normalized artist and cleaned title
      final key = '${cleanedArtist}_$cleanedTitle';

      candidateMap.putIfAbsent(key, () => []).add(song);
      displayTitleMap.putIfAbsent(key, () => _cleanDisplayTitle(song.title));
    }

    final List<MergeCandidateGroup> candidates = [];

    for (final entry in candidateMap.entries) {
      final groupSongs = entry.value;
      if (groupSongs.length < 2) continue;

      // Check if all songs in this group are already merged together in an existing group
      final filenames = groupSongs.map((s) => s.filename).toSet();
      final alreadyMergedTogether = existingGroupSets.any(
        (groupSet) => filenames.every((f) => groupSet.contains(f)),
      );

      if (alreadyMergedTogether) continue;

      final displayTitle = displayTitleMap[entry.key] ?? groupSongs.first.title;

      candidates.add(
        MergeCandidateGroup(
          title: displayTitle,
          songs: groupSongs,
        ),
      );
    }

    candidates
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return candidates;
  }

  /// Cleans title by removing brackets, version tags, features, and non-alphanumeric chars.
  static String _cleanTitle(String title) {
    var cleaned = title.toLowerCase();

    // Remove text inside brackets/parentheses if it contains version keywords
    final versionPattern = RegExp(
      r'[\(\[\{].*?(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb).*?[\)\]\}]',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(versionPattern, '');

    // Remove common trailing version descriptions e.g. "- remix", "- live"
    final trailingPattern = RegExp(
      r'-\s*(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod).*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(trailingPattern, '');

    // Remove non-alphanumeric characters
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9\s]'), '');

    // Collapse whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  /// Normalizes artist name for comparison.
  static String _cleanArtist(String artist) {
    var cleaned = artist.toLowerCase();

    // Remove feat/ft details from artist field if any
    cleaned = cleaned.replaceAll(
        RegExp(r'(feat\.|ft\.).*$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  /// Cleans title for user display (e.g. "Blinding Lights (Remix)" -> "Blinding Lights")
  static String _cleanDisplayTitle(String title) {
    var cleaned = title;

    final versionPattern = RegExp(
      r'\s*[\(\[\{].*?(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb).*?[\)\]\}]',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(versionPattern, '');

    final trailingPattern = RegExp(
      r'\s*-\s*(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod).*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(trailingPattern, '');

    cleaned = cleaned.trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }
}

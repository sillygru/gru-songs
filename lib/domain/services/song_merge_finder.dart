import '../../models/song.dart';

class MergeCandidateGroup {
  final String title;
  final List<Song> songs;

  const MergeCandidateGroup({
    required this.title,
    required this.songs,
  });
}

class SongMergeFinder {
  const SongMergeFinder._();

  static final RegExp _bracketPattern = RegExp(
    r'[\(\[\{].*?(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle).*?[\)\]\}]',
    caseSensitive: false,
  );

  static final RegExp _trailingDashPattern = RegExp(
    r'-\s*(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle).*$',
    caseSensitive: false,
  );

  static final RegExp _trailingBarePattern = RegExp(
    r'\s+(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle)\s*.*$',
    caseSensitive: false,
  );

  static final RegExp _extPattern = RegExp(
    r'\.(mp3|m4a|wav|flac|ogg|wma|aac|opus|webm|mkv|mp4|m4v|avi|webmexport)\s*$',
    caseSensitive: false,
  );

  static List<MergeCandidateGroup> findCandidates(
    List<Song> songs,
    Map<String, List<String>> existingMergedGroups,
  ) {
    if (songs.length < 2) return [];

    final existingGroupSets = existingMergedGroups.values
        .map((filenames) => filenames.toSet())
        .toList();

    final Map<String, List<Song>> candidateMap = {};
    final Map<String, String> displayTitleMap = {};

    for (final song in songs) {
      final cleanedTitle = _cleanTitle(song.title);
      final cleanedArtist = _cleanArtist(song.artist);

      if (cleanedTitle.isEmpty) continue;

      final key = '${cleanedArtist}_$cleanedTitle';

      candidateMap.putIfAbsent(key, () => []).add(song);
      displayTitleMap.putIfAbsent(key, () => _cleanDisplayTitle(song.title));
    }

    final List<MergeCandidateGroup> candidates = [];

    for (final entry in candidateMap.entries) {
      final groupSongs = entry.value;
      if (groupSongs.length < 2) continue;

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

  static String _cleanTitle(String title) {
    var cleaned = title.toLowerCase();

    cleaned = cleaned.replaceAll(_bracketPattern, '');
    cleaned = cleaned.replaceAll(_trailingDashPattern, '');
    cleaned = cleaned.replaceAll(_trailingBarePattern, '');
    cleaned = cleaned.replaceAll(_extPattern, '');

    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  static String _cleanArtist(String artist) {
    var cleaned = artist.toLowerCase();

    cleaned = cleaned.replaceAll(
        RegExp(r'(feat\.|ft\.).*$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  static String _cleanDisplayTitle(String title) {
    var cleaned = title;

    final displayBracket = RegExp(
      r'\s*[\(\[\{].*?(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle).*?[\)\]\}]',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(displayBracket, '');

    final displayTrailing = RegExp(
      r'\s*-\s*(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle).*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(displayTrailing, '');

    final displayBare = RegExp(
      r'\s+(remix|live|acoustic|instrumental|edit|extended|version|mix|feat|ft|cover|demo|slowed|speed|audio|prod|reverb|hardstyle|nightcore|sped|ultra|phonk|techno|euphoric|tiktok|rave|trance|dubstep|bass|boosted|jumpstyle)\s*.*$',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(displayBare, '');

    cleaned = cleaned.replaceAll(_extPattern, '');

    cleaned = cleaned.trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }
}

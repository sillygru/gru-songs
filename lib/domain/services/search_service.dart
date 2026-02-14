import '../../models/song.dart';
import '../models/search_filter.dart';
import '../models/search_result.dart';
import '../../data/repositories/search_index_repository.dart';

/// Service for performing searches across the music library
///
/// This service coordinates between the search index repository and
/// the song data to provide fast, filtered search results.
class SearchService {
  final SearchIndexRepository _indexRepository;

  SearchService({SearchIndexRepository? indexRepository})
      : _indexRepository = indexRepository ?? SearchIndexRepository();

  /// Initializes the search service
  Future<void> init() async {
    await _indexRepository.init();
  }

  /// Performs a search with the given query and filter state
  ///
  /// Returns a list of search results that match the criteria
  Future<List<SearchResult>> search({
    required String query,
    required SearchFilterState filterState,
    required List<Song> allSongs,
  }) async {
    if (query.isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) {
      return [];
    }

    // Determine which fields to search based on filter state
    final searchTitles = filterState.all || filterState.songs;
    final searchArtists = filterState.all || filterState.artists;
    final searchAlbums = filterState.all || filterState.albums;
    final searchLyrics =
        filterState.all || filterState.songs || filterState.lyrics;

    // Get matches from the index
    final matches = await _indexRepository.search(
      query: lowerQuery,
      searchTitles: searchTitles,
      searchArtists: searchArtists,
      searchAlbums: searchAlbums,
      searchLyrics: searchLyrics,
    );

    // Create a lookup map for songs
    final songMap = {for (var song in allSongs) song.filename: song};

    // Build search results
    final results = <SearchResult>[];
    for (final match in matches) {
      final song = songMap[match.filename];
      if (song == null) continue;

      final matchedFilters = <SearchFilterType>{};

      // Determine which filters matched
      switch (match.matchType) {
        case SearchMatchType.title:
          matchedFilters.add(SearchFilterType.songs);
          break;
        case SearchMatchType.artist:
          matchedFilters.add(SearchFilterType.artists);
          break;
        case SearchMatchType.album:
          matchedFilters.add(SearchFilterType.albums);
          break;
        case SearchMatchType.lyrics:
          matchedFilters.add(SearchFilterType.lyrics);
          break;
      }

      // Create lyrics match if applicable
      LyricsMatch? lyricsMatch;
      if (match.matchType == SearchMatchType.lyrics && match.fullLine != null) {
        lyricsMatch = LyricsMatch(
          matchedText: match.matchedText,
          fullLine: match.fullLine!,
        );
      }

      results.add(SearchResult(
        song: song,
        lyricsMatch: lyricsMatch,
        matchedFilters: matchedFilters,
      ));
    }

    // Sort results: title matches first, then artist, then album, then lyrics
    results.sort((a, b) {
      final priorityA = _getMatchPriority(a);
      final priorityB = _getMatchPriority(b);
      return priorityA.compareTo(priorityB);
    });

    return results;
  }

  /// Gets priority for sorting (lower = higher priority)
  int _getMatchPriority(SearchResult result) {
    if (result.matchedTitle) return 0;
    if (result.matchedArtist) return 1;
    if (result.matchedAlbum) return 2;
    if (result.hasLyricsMatch) return 3;
    return 4;
  }

  /// Groups search results by artist
  Map<String, List<SearchResult>> groupByArtist(List<SearchResult> results) {
    final groups = <String, List<SearchResult>>{};
    for (final result in results) {
      final artist = result.song.artist;
      groups.putIfAbsent(artist, () => []).add(result);
    }
    return groups;
  }

  /// Groups search results by album
  Map<String, List<SearchResult>> groupByAlbum(List<SearchResult> results) {
    final groups = <String, List<SearchResult>>{};
    for (final result in results) {
      final album = result.song.album;
      groups.putIfAbsent(album, () => []).add(result);
    }
    return groups;
  }

  /// Rebuilds the search index from a list of songs
  ///
  /// This should be called during library scanning
  Future<void> rebuildIndex(List<Song> songs) async {
    await _indexRepository.rebuildIndex(songs);
  }

  /// Updates a single song in the index
  Future<void> updateSong(Song song) async {
    await _indexRepository.upsertSong(song);
  }

  /// Removes a song from the index
  Future<void> removeSong(String filename) async {
    await _indexRepository.removeSong(filename);
  }

  /// Clears the search index
  Future<void> clearIndex() async {
    await _indexRepository.clear();
  }

  /// Gets statistics about the search index
  Future<SearchIndexStats> getIndexStats() async {
    final stats = await _indexRepository.getStats();
    return SearchIndexStats(
      totalEntries: stats.totalEntries,
      entriesWithLyrics: stats.entriesWithLyrics,
      totalLyricsChars: stats.totalLyricsChars,
      lastUpdated: stats.lastUpdated,
    );
  }

  /// Disposes of resources
  Future<void> dispose() async {
    await _indexRepository.close();
  }
}

/// Statistics about the search index
class SearchIndexStats {
  final int totalEntries;
  final int entriesWithLyrics;
  final int totalLyricsChars;
  final DateTime? lastUpdated;

  const SearchIndexStats({
    required this.totalEntries,
    required this.entriesWithLyrics,
    required this.totalLyricsChars,
    this.lastUpdated,
  });

  factory SearchIndexStats.empty() {
    return const SearchIndexStats(
      totalEntries: 0,
      entriesWithLyrics: 0,
      totalLyricsChars: 0,
      lastUpdated: null,
    );
  }
}

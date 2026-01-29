import 'package:equatable/equatable.dart';
import '../../models/song.dart';
import 'search_filter.dart';

/// Represents a match found in lyrics with the matched text
class LyricsMatch extends Equatable {
  final String matchedText;
  final String fullLine;
  final Duration? timestamp;

  const LyricsMatch({
    required this.matchedText,
    required this.fullLine,
    this.timestamp,
  });

  @override
  List<Object?> get props => [matchedText, fullLine, timestamp];
}

/// Represents a search result with optional lyrics match information
class SearchResult extends Equatable {
  final Song song;
  final LyricsMatch? lyricsMatch;
  final Set<SearchFilterType> matchedFilters;

  const SearchResult({
    required this.song,
    this.lyricsMatch,
    required this.matchedFilters,
  });

  /// Returns true if this result matched through lyrics
  bool get hasLyricsMatch => lyricsMatch != null;

  /// Returns true if this result matched through song title
  bool get matchedTitle => matchedFilters.contains(SearchFilterType.songs);

  /// Returns true if this result matched through artist name
  bool get matchedArtist => matchedFilters.contains(SearchFilterType.artists);

  /// Returns true if this result matched through album name
  bool get matchedAlbum => matchedFilters.contains(SearchFilterType.albums);

  SearchResult copyWith({
    Song? song,
    LyricsMatch? lyricsMatch,
    Set<SearchFilterType>? matchedFilters,
  }) {
    return SearchResult(
      song: song ?? this.song,
      lyricsMatch: lyricsMatch ?? this.lyricsMatch,
      matchedFilters: matchedFilters ?? this.matchedFilters,
    );
  }

  @override
  List<Object?> get props => [song, lyricsMatch, matchedFilters];
}

/// Grouped search results for artist/album views
class GroupedSearchResults extends Equatable {
  final String name;
  final List<SearchResult> songs;
  final SearchFilterType groupType;

  const GroupedSearchResults({
    required this.name,
    required this.songs,
    required this.groupType,
  });

  @override
  List<Object?> get props => [name, songs, groupType];
}

/// Complete search results containing all matches
class SearchResults extends Equatable {
  final List<SearchResult> songs;
  final List<GroupedSearchResults> artists;
  final List<GroupedSearchResults> albums;
  final String query;
  final SearchFilterState filterState;

  const SearchResults({
    required this.songs,
    required this.artists,
    required this.albums,
    required this.query,
    required this.filterState,
  });

  /// Returns true if there are any results
  bool get hasResults =>
      songs.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty;

  /// Returns total count of all results
  int get totalCount => songs.length + artists.length + albums.length;

  /// Empty results factory
  factory SearchResults.empty(String query, SearchFilterState filterState) {
    return SearchResults(
      songs: const [],
      artists: const [],
      albums: const [],
      query: query,
      filterState: filterState,
    );
  }

  @override
  List<Object?> get props => [songs, artists, albums, query, filterState];
}

import 'package:equatable/equatable.dart';

/// Enum representing the different types of search filters
enum SearchFilterType {
  all,
  songs,
  artists,
  albums,
  lyrics,
}

/// Extension to get display name for filter type
extension SearchFilterTypeExtension on SearchFilterType {
  String get displayName {
    switch (this) {
      case SearchFilterType.all:
        return 'All';
      case SearchFilterType.songs:
        return 'Songs';
      case SearchFilterType.artists:
        return 'Artists';
      case SearchFilterType.albums:
        return 'Albums';
      case SearchFilterType.lyrics:
        return 'Lyrics';
    }
  }
}

/// Model representing the state of search filters
///
/// The filter logic follows these rules:
/// - Selecting "All" deselects all specific filters
/// - Selecting any specific filter deselects "All"
/// - Multiple specific filters can be selected simultaneously
class SearchFilterState extends Equatable {
  final bool all;
  final bool songs;
  final bool artists;
  final bool albums;
  final bool lyrics;
  final List<String> selectedMoodIds;

  const SearchFilterState({
    this.all = true,
    this.songs = false,
    this.artists = false,
    this.albums = false,
    this.lyrics = false,
    this.selectedMoodIds = const [],
  });

  /// Factory constructor for "All" filter (default)
  factory SearchFilterState.all() => const SearchFilterState(all: true);

  /// Returns true if any specific filter is selected (not "All")
  bool get hasSpecificFilters => songs || artists || albums || lyrics;
  bool get hasMoodFilter => selectedMoodIds.isNotEmpty;

  /// Returns true if lyrics should be searched
  /// Lyrics are searched when "All" is selected OR when "Songs" is selected
  bool get shouldSearchLyrics => all || songs;

  /// Returns list of active filter types
  List<SearchFilterType> get activeFilters {
    if (all) return [SearchFilterType.all];
    final filters = <SearchFilterType>[];
    if (songs) filters.add(SearchFilterType.songs);
    if (artists) filters.add(SearchFilterType.artists);
    if (albums) filters.add(SearchFilterType.albums);
    if (lyrics) filters.add(SearchFilterType.lyrics);
    return filters.isEmpty ? [SearchFilterType.all] : filters;
  }

  /// Toggles a specific filter type
  /// Handles the mutual exclusivity between "All" and specific filters
  SearchFilterState toggleFilter(SearchFilterType type) {
    switch (type) {
      case SearchFilterType.all:
        // Selecting "All" clears all specific filters
        return const SearchFilterState(all: true);
      case SearchFilterType.songs:
        return _toggleSpecificFilter(songs: !songs);
      case SearchFilterType.artists:
        return _toggleSpecificFilter(artists: !artists);
      case SearchFilterType.albums:
        return _toggleSpecificFilter(albums: !albums);
      case SearchFilterType.lyrics:
        return _toggleSpecificFilter(lyrics: !lyrics);
    }
  }

  /// Helper to toggle a specific filter and clear "All"
  SearchFilterState _toggleSpecificFilter({
    bool? songs,
    bool? artists,
    bool? albums,
    bool? lyrics,
  }) {
    return SearchFilterState(
      all: false,
      songs: songs ?? this.songs,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      lyrics: lyrics ?? this.lyrics,
      selectedMoodIds: selectedMoodIds,
    );
  }

  /// Sets a specific filter to selected state (for UI chip selection)
  SearchFilterState selectFilter(SearchFilterType type) {
    switch (type) {
      case SearchFilterType.all:
        return const SearchFilterState(all: true);
      case SearchFilterType.songs:
        return SearchFilterState(
          all: false,
          songs: true,
          artists: artists,
          albums: albums,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
      case SearchFilterType.artists:
        return SearchFilterState(
          all: false,
          songs: songs,
          artists: true,
          albums: albums,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
      case SearchFilterType.albums:
        return SearchFilterState(
          all: false,
          songs: songs,
          artists: artists,
          albums: true,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
      case SearchFilterType.lyrics:
        return SearchFilterState(
          all: false,
          songs: songs,
          artists: artists,
          albums: albums,
          lyrics: true,
          selectedMoodIds: selectedMoodIds,
        );
    }
  }

  /// Deselects a specific filter
  SearchFilterState deselectFilter(SearchFilterType type) {
    switch (type) {
      case SearchFilterType.all:
        // Cannot deselect "All" without selecting something else
        return this;
      case SearchFilterType.songs:
        final newState = SearchFilterState(
          all: false,
          songs: false,
          artists: artists,
          albums: albums,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
        return newState._fallbackToAllIfEmpty();
      case SearchFilterType.artists:
        final newState = SearchFilterState(
          all: false,
          songs: songs,
          artists: false,
          albums: albums,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
        return newState._fallbackToAllIfEmpty();
      case SearchFilterType.albums:
        final newState = SearchFilterState(
          all: false,
          songs: songs,
          artists: artists,
          albums: false,
          lyrics: lyrics,
          selectedMoodIds: selectedMoodIds,
        );
        return newState._fallbackToAllIfEmpty();
      case SearchFilterType.lyrics:
        final newState = SearchFilterState(
          all: false,
          songs: songs,
          artists: artists,
          albums: albums,
          lyrics: false,
          selectedMoodIds: selectedMoodIds,
        );
        return newState._fallbackToAllIfEmpty();
    }
  }

  /// Falls back to "All" if no specific filters are selected
  SearchFilterState _fallbackToAllIfEmpty() {
    if (!hasSpecificFilters) {
      return SearchFilterState(
        all: true,
        selectedMoodIds: selectedMoodIds,
      );
    }
    return this;
  }

  SearchFilterState withMoodIds(Iterable<String> moodIds) {
    return SearchFilterState(
      all: all,
      songs: songs,
      artists: artists,
      albums: albums,
      lyrics: lyrics,
      selectedMoodIds: moodIds.toSet().toList(),
    );
  }

  /// Returns true if the given filter type is selected
  bool isSelected(SearchFilterType type) {
    switch (type) {
      case SearchFilterType.all:
        return all;
      case SearchFilterType.songs:
        return songs;
      case SearchFilterType.artists:
        return artists;
      case SearchFilterType.albums:
        return albums;
      case SearchFilterType.lyrics:
        return lyrics;
    }
  }

  @override
  List<Object?> get props => [
        all,
        songs,
        artists,
        albums,
        lyrics,
        selectedMoodIds,
      ];

  @override
  String toString() {
    return 'SearchFilterState(all: $all, songs: $songs, artists: $artists, albums: $albums, lyrics: $lyrics, selectedMoodIds: $selectedMoodIds)';
  }
}

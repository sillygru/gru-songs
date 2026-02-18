import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/search_filter.dart';
import '../domain/models/search_result.dart';
import '../domain/services/search_service.dart';
import 'providers.dart';

/// Provider for the search service
final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

/// Provider for the search filter state using Notifier
final searchFilterProvider =
    NotifierProvider<SearchFilterNotifier, SearchFilterState>(() {
  return SearchFilterNotifier();
});

/// Notifier for managing search filter state
class SearchFilterNotifier extends Notifier<SearchFilterState> {
  @override
  SearchFilterState build() {
    return const SearchFilterState(all: true);
  }

  /// Toggles a filter type
  void toggleFilter(SearchFilterType type) {
    state = state.toggleFilter(type);
  }

  /// Selects a specific filter
  void selectFilter(SearchFilterType type) {
    state = state.selectFilter(type);
  }

  /// Deselects a specific filter
  void deselectFilter(SearchFilterType type) {
    state = state.deselectFilter(type);
  }

  /// Resets to default (All)
  void reset() {
    state = const SearchFilterState(all: true);
  }

  void toggleMood(String moodId) {
    final selected = state.selectedMoodIds.toSet();
    if (selected.contains(moodId)) {
      selected.remove(moodId);
    } else {
      selected.add(moodId);
    }
    state = state.withMoodIds(selected);
  }

  void clearMoods() {
    state = state.withMoodIds(const <String>[]);
  }
}

/// Provider for search results
final searchResultsProvider =
    FutureProvider.family<List<SearchResult>, String>((ref, query) async {
  // Watch filter state - this is the primary dependency
  final filterState = ref.watch(searchFilterProvider);

  // Read songs and user data without watching to avoid circular dependencies
  final songsAsync = ref.watch(songsProvider);
  final userData = ref.watch(userDataProvider);
  final searchService = ref.read(searchServiceProvider);

  if (query.isEmpty) {
    return [];
  }

  // Initialize search service for the current user
  await searchService.init();

  return songsAsync.when(
    data: (songs) async {
      final results = await searchService.search(
        query: query,
        filterState: filterState,
        allSongs: songs,
      );
      if (filterState.selectedMoodIds.isEmpty) return results;

      final selectedMoodIds = filterState.selectedMoodIds.toSet();
      return results
          .where(
              (r) => userData.songHasAnyMood(r.song.filename, selectedMoodIds))
          .toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Provider for debounced search query
final debouncedSearchQueryProvider =
    NotifierProvider<DebouncedSearchNotifier, String>(() {
  return DebouncedSearchNotifier();
});

/// Notifier that debounces search query changes
class DebouncedSearchNotifier extends Notifier<String> {
  @override
  String build() {
    return '';
  }

  void setQuery(String query) {
    state = query;
  }
}

/// Provider for search index stats
final searchIndexStatsProvider = FutureProvider<SearchIndexStats>((ref) async {
  final searchService = ref.watch(searchServiceProvider);

  await searchService.init();

  final stats = await searchService.getIndexStats();
  return SearchIndexStats(
    totalEntries: stats.totalEntries,
    entriesWithLyrics: stats.entriesWithLyrics,
    totalLyricsChars: stats.totalLyricsChars,
    lastUpdated: stats.lastUpdated,
  );
});

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

/// Mixin for widgets that need search functionality
mixin SearchMixin<T> {
  /// Debounces search operations
  Future<void> debouncedSearch(
    String query,
    void Function(String) onSearch,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    onSearch(query);
  }
}

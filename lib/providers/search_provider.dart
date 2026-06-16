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
  final filterState = ref.watch(searchFilterProvider);

  final songsAsync = ref.watch(songsProvider);
  final userData = ref.watch(userDataProvider);
  final searchService = ref.read(searchServiceProvider);

  if (query.isEmpty) {
    return [];
  }

  return songsAsync.when(
    data: (songs) async {
      final results = await searchService.search(
        query: query,
        filterState: filterState,
        allSongs: songs,
      );
      if (filterState.selectedMoodIds.isEmpty) return results;
      return results
          .where((r) => userData.songHasAnyMood(
              r.song.filename, filterState.selectedMoodIds.toSet()))
          .toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

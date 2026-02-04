import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/search_filter.dart';
import '../../domain/models/search_result.dart';
import '../../providers/providers.dart';
import '../../providers/search_provider.dart';
import '../../services/audio_player_manager.dart';
import '../widgets/search_filter_chips.dart';
import '../widgets/search_result_item.dart';
import '../widgets/bulk_selection_bar.dart';
import '../../providers/selection_provider.dart';
import 'song_list_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = value.toLowerCase().trim();
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(searchFilterProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final selectionState = ref.watch(selectionProvider);

    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selectionState.isSelectionMode) {
          ref.read(selectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums...',
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            onChanged: _onSearchChanged,
          ),
          actions: [
            if (_query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearSearch,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              child: const SearchFilterChips(),
            ),
          ),
        ),
        body: _query.isEmpty
            ? _buildEmptyState(context)
            : _buildSearchResults(context, audioManager, filterState),
        bottomNavigationBar:
            selectionState.isSelectionMode ? const BulkSelectionBar() : null,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 80,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 16),
          const Text(
            'Search your music collection',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Find songs, artists, albums, and lyrics',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    AudioPlayerManager audioManager,
    SearchFilterState filterState,
  ) {
    final searchResultsAsync = ref.watch(searchResultsProvider(_query));

    return searchResultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return _buildNoResultsState(context);
        }

        // Group results based on filter state
        final displayResults = _organizeResults(results, filterState);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: displayResults.length,
          itemBuilder: (context, index) {
            final item = displayResults[index];
            return _buildResultItem(item, audioManager, context);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error searching: $err'),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found for "$_query"',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Try different keywords or check your filters',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _organizeResults(
    List<SearchResult> results,
    SearchFilterState filterState,
  ) {
    // When filtering by specific types, show appropriate groupings
    // Note: When "All" is selected with artists/albums, we still want to show grouped results
    final showArtists =
        filterState.artists || (filterState.all && _hasArtistMatches(results));
    final showAlbums =
        filterState.albums || (filterState.all && _hasAlbumMatches(results));
    final showSongs =
        filterState.songs || filterState.all || filterState.lyrics;

    if (showArtists && !showSongs && !showAlbums) {
      // Group by artist (only artists filter selected)
      final artistGroups = <String, List<SearchResult>>{};
      for (final result in results) {
        if (result.matchedArtist) {
          artistGroups.putIfAbsent(result.song.artist, () => []).add(result);
        }
      }
      return artistGroups.entries
          .map((e) => _ArtistGroup(e.key, e.value))
          .toList();
    }

    if (showAlbums && !showSongs && !showArtists) {
      // Group by album (only albums filter selected)
      final albumGroups = <String, List<SearchResult>>{};
      for (final result in results) {
        if (result.matchedAlbum) {
          final key = '${result.song.album}|${result.song.artist}';
          albumGroups.putIfAbsent(key, () => []).add(result);
        }
      }
      return albumGroups.entries
          .map((e) => _AlbumGroup(
                e.value.first.song.album,
                e.value.first.song.artist,
                e.value,
              ))
          .toList();
    }

    // When multiple types are selected (e.g., All + Artists, or All + Albums),
    // show sections for each type
    if ((filterState.all || filterState.songs) && (showArtists || showAlbums)) {
      final organized = <dynamic>[];

      // Add artists section first
      if (showArtists) {
        final artistGroups = <String, List<SearchResult>>{};
        for (final result in results) {
          if (result.matchedArtist) {
            artistGroups.putIfAbsent(result.song.artist, () => []).add(result);
          }
        }
        if (artistGroups.isNotEmpty) {
          organized.add(const _SectionHeader('Artists'));
          organized.addAll(
            artistGroups.entries.map((e) => _ArtistGroup(e.key, e.value)),
          );
        }
      }

      // Add albums section
      if (showAlbums) {
        final albumGroups = <String, List<SearchResult>>{};
        for (final result in results) {
          if (result.matchedAlbum) {
            final key = '${result.song.album}|${result.song.artist}';
            albumGroups.putIfAbsent(key, () => []).add(result);
          }
        }
        if (albumGroups.isNotEmpty) {
          organized.add(const _SectionHeader('Albums'));
          organized.addAll(
            albumGroups.entries.map((e) => _AlbumGroup(
                  e.value.first.song.album,
                  e.value.first.song.artist,
                  e.value,
                )),
          );
        }
      }

      // Add songs section last
      if (showSongs) {
        final songResults = results
            .where((r) =>
                r.matchedTitle ||
                r.hasLyricsMatch ||
                (filterState.songs && (r.matchedTitle || r.hasLyricsMatch)))
            .toList();
        if (songResults.isNotEmpty) {
          organized.add(const _SectionHeader('Songs'));
          organized.addAll(songResults);
        }
      }

      return organized;
    }

    // Default: return all results as individual items
    return results;
  }

  bool _hasArtistMatches(List<SearchResult> results) {
    return results.any((r) => r.matchedArtist);
  }

  bool _hasAlbumMatches(List<SearchResult> results) {
    return results.any((r) => r.matchedAlbum);
  }

  Widget _buildResultItem(
    dynamic item,
    AudioPlayerManager audioManager,
    BuildContext context,
  ) {
    if (item is SearchResult) {
      return SearchResultItem(
        result: item,
        searchQuery: _query,
        heroTagPrefix: 'search',
        onTap: () => _playSearchResult(item, audioManager),
      );
    } else if (item is _ArtistGroup) {
      return ArtistSearchResultItem(
        artistName: item.artistName,
        songs: item.results.map((r) => r.song).toList(),
        onTap: () => _showArtistSongs(item.artistName, item.results),
      );
    } else if (item is _AlbumGroup) {
      return AlbumSearchResultItem(
        albumName: item.albumName,
        artistName: item.artistName,
        songs: item.results.map((r) => r.song).toList(),
        onTap: () =>
            _showAlbumSongs(item.albumName, item.artistName, item.results),
      );
    } else if (item is _SectionHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          item.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _playSearchResult(SearchResult result, AudioPlayerManager audioManager) {
    // Get all search results to use as context queue
    final allResults = ref.read(searchResultsProvider(_query)).value ?? [];
    final songs = allResults.map((r) => r.song).toList();

    audioManager.playSong(result.song, contextQueue: songs);
  }

  void _showArtistSongs(String artistName, List<SearchResult> results) {
    final songs = results.map((r) => r.song).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SongListScreen(
          title: artistName,
          songs: songs,
        ),
      ),
    );
  }

  void _showAlbumSongs(
      String albumName, String artistName, List<SearchResult> results) {
    final songs = results.map((r) => r.song).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SongListScreen(
          title: albumName,
          songs: songs,
        ),
      ),
    );
  }
}

// Helper classes for grouping
class _ArtistGroup {
  final String artistName;
  final List<SearchResult> results;
  _ArtistGroup(this.artistName, this.results);
}

class _AlbumGroup {
  final String albumName;
  final String artistName;
  final List<SearchResult> results;
  _AlbumGroup(this.albumName, this.artistName, this.results);
}

class _SectionHeader {
  final String title;
  const _SectionHeader(this.title);
}

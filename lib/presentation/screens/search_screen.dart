import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../widgets/song_list_item.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searchLibrary = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search songs, artists...',
            border: InputBorder.none,
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5)),
          ),
          onChanged: (value) {
            setState(() {
              _query = value.toLowerCase();
            });
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: !_searchLibrary,
                  onSelected: (selected) {
                    if (selected) setState(() => _searchLibrary = false);
                  },
                  showCheckmark: false,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Library'),
                  selected: _searchLibrary,
                  onSelected: (selected) {
                    if (selected) setState(() => _searchLibrary = true);
                  },
                  showCheckmark: false,
                ),
              ],
            ),
          ),
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                var filteredSongs = songs.where((song) {
                  final matchesQuery =
                      song.title.toLowerCase().contains(_query) ||
                          song.artist.toLowerCase().contains(_query) ||
                          song.album.toLowerCase().contains(_query);

                  if (!matchesQuery) return false;

                  if (_searchLibrary) {
                    return userData.isFavorite(song.filename);
                  }

                  return true;
                }).toList();

                if (_query.isEmpty && !_searchLibrary) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search,
                            size: 80,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest),
                        const SizedBox(height: 16),
                        const Text('Search your music collection'),
                      ],
                    ),
                  );
                }

                if (filteredSongs.isEmpty) {
                  return const Center(child: Text('No results found'));
                }

                return ListView.builder(
                  itemCount: filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = filteredSongs[index];
                    final isPlaying =
                        audioManager.currentSongNotifier.value?.filename ==
                            song.filename;

                    return SongListItem(
                      song: song,
                      isPlaying: isPlaying,
                      heroTagPrefix: 'search',
                      onTap: () {
                        audioManager.playSong(song,
                            contextQueue: filteredSongs);
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

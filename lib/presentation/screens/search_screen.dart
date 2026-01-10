import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/song_options_menu.dart';

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
    final apiService = ref.watch(apiServiceProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search songs, artists...',
            border: InputBorder.none,
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
                ChoiceChip(
                  label: const Text('All'),
                  selected: !_searchLibrary,
                  onSelected: (selected) {
                    if (selected) setState(() => _searchLibrary = false);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Library'),
                  selected: _searchLibrary,
                  onSelected: (selected) {
                    if (selected) setState(() => _searchLibrary = true);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                var filteredSongs = songs.where((song) {
                  final matchesQuery = song.title.toLowerCase().contains(_query) ||
                      song.artist.toLowerCase().contains(_query) ||
                      (song.album?.toLowerCase().contains(_query) ?? false);
                  
                  if (!matchesQuery) return false;

                  if (_searchLibrary) {
                    final isFavorite = userData.favorites.contains(song.filename);
                    final isInPlaylist = userData.playlists.any((p) => p.songs.any((s) => s.filename == song.filename));
                    return isFavorite || isInPlaylist;
                  }

                  return true;
                }).toList();

                if (_query.isEmpty && !_searchLibrary) {
                   return const Center(child: Text('Search for your favorite music'));
                }

                if (filteredSongs.isEmpty) {
                  return const Center(child: Text('No results found'));
                }

                return ListView.builder(
                  itemCount: filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = filteredSongs[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: song.coverUrl != null
                              ? apiService.getFullUrl(song.coverUrl!)
                              : apiService.getFullUrl('/stream/cover.jpg'),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.music_note),
                        ),
                      ),
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      onTap: () {
                        // Play the filtered list from this point
                        audioManager.init(filteredSongs);
                        audioManager.player.seek(Duration.zero, index: index);
                        audioManager.player.play();
                      },
                      onLongPress: () {
                        showSongOptionsMenu(context, ref, song.filename, song.title);
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

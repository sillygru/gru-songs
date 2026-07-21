import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
import '../components/app_feedback.dart';
import '../components/app_media_card.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';
import '../components/app_sheet.dart';

class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  String _sortBy = 'name'; // 'name', 'artist', 'songs'
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search albums...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Albums'),
        leading: _isSearching
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            icon: Icon(_isSearching ? Icons.close : Icons.search),
          ),
          IconButton(
            onPressed: () => _showSortOptions(context),
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: songsAsync.when(
        data: (songs) {
          var albumMap = LibraryLogic.groupByAlbum(songs);

          if (_searchQuery.isNotEmpty) {
            albumMap = Map.fromEntries(
              albumMap.entries.where((entry) =>
                  entry.key.toLowerCase().contains(_searchQuery.toLowerCase())),
            );
          }

          final sortedAlbums = _sortAlbums(albumMap);

          if (sortedAlbums.isEmpty) {
            return _buildEmptyState(context, colorScheme);
          }

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s4,
              AppTokens.s4,
              AppTokens.scrollBottomInset,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: AppTokens.s4,
              mainAxisSpacing: AppTokens.s4,
            ),
            itemCount: sortedAlbums.length,
            itemBuilder: (context, index) {
              final album = sortedAlbums[index];
              final albumSongs = albumMap[album]!;
              final artist = albumSongs.isNotEmpty
                  ? albumSongs[0].artist
                  : 'Unknown Artist';

              return _buildAlbumCard(
                context,
                album: album,
                artist: artist,
                songs: albumSongs,
                colorScheme: colorScheme,
              );
            },
          );
        },
        loading: () => const AppLoading(),
        error: (e, _) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load albums',
          message: '$e',
          tone: AppTone.danger,
        ),
      ),
    );
  }

  Widget _buildAlbumCard(
    BuildContext context, {
    required String album,
    required String artist,
    required List<Song> songs,
    required ColorScheme colorScheme,
  }) {
    return AppMediaCard(
      expand: true,
      title: album,
      subtitle: '$artist · ${collectionSummary(songs)}',
      artwork: FolderGridImage(songs: songs, isGridItem: true),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SongListScreen(title: album, songs: songs),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.album_outlined,
            size: 100,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No albums found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add music to your library to see albums',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _sortAlbums(Map<String, List<Song>> albumMap) {
    final albums = albumMap.keys.toList();

    switch (_sortBy) {
      case 'artist':
        albums.sort((a, b) {
          final artistA = albumMap[a]!.isNotEmpty ? albumMap[a]![0].artist : '';
          final artistB = albumMap[b]!.isNotEmpty ? albumMap[b]![0].artist : '';
          final artistCompare =
              artistA.toLowerCase().compareTo(artistB.toLowerCase());
          if (artistCompare != 0) return artistCompare;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
      case 'songs':
        albums.sort((a, b) {
          final countCompare =
              albumMap[b]!.length.compareTo(albumMap[a]!.length);
          if (countCompare != 0) return countCompare;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
      case 'name':
      default:
        albums.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
    }

    return albums;
  }

  void _showSortOptions(BuildContext context) {
    showAppSheet(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sort_by_alpha),
            title: const Text('Name (A-Z)'),
            trailing: _sortBy == 'name' ? const Icon(Icons.check) : null,
            onTap: () {
              setState(() => _sortBy = 'name');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Artist'),
            trailing: _sortBy == 'artist' ? const Icon(Icons.check) : null,
            onTap: () {
              setState(() => _sortBy = 'artist');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Most Songs'),
            trailing: _sortBy == 'songs' ? const Icon(Icons.check) : null,
            onTap: () {
              setState(() => _sortBy = 'songs');
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

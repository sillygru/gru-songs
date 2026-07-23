import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
import '../components/app_feedback.dart';
import '../components/app_media_card.dart';
import '../components/app_sheet.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';

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
            return const AppEmptyState(
              icon: Icons.album_rounded,
              title: 'No albums found',
              message: 'Add music to your library to see albums.',
            );
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
  }) {
    return AppMediaCard(
      expand: true,
      title: album,
      subtitle: '$artist · ${collectionSummary(songs)}',
      artwork: FolderGridImage(songs: songs, isGridItem: true),
      onTap: () => context.pushApp(SongListScreen(title: album, songs: songs)),
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
      title: 'Sort albums',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortAction(
              sheetContext, 'name', Icons.sort_by_alpha_rounded, 'Name (A-Z)'),
          _sortAction(sheetContext, 'artist', Icons.person_rounded, 'Artist'),
          _sortAction(
              sheetContext, 'songs', Icons.music_note_rounded, 'Most Songs'),
        ],
      ),
    );
  }

  Widget _sortAction(
    BuildContext sheetContext,
    String value,
    IconData icon,
    String label,
  ) {
    final selected = _sortBy == value;
    return AppSheetAction(
      icon: icon,
      label: label,
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppTokens.accentOf(context, ref))
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(sheetContext);
      },
    );
  }
}

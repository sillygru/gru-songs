import 'dart:io';
import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/artist_album_art_provider.dart';
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../../services/online_metadata_service.dart';
import '../../services/passive_art_fetcher_service.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
import '../components/app_feedback.dart';
import '../components/app_media_card.dart';
import '../components/app_sheet.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';
import '../components/song_actions.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  String _sortBy = 'songs'; // 'songs', 'name', 'artist'
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

    return AmbientScaffold(
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
                icon: const AppIcon(AppIcons.arrowBack),
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
            icon: AppIcon(_isSearching ? AppIcons.close : AppIcons.search),
          ),
          IconButton(
            onPressed: () => _showSortOptions(context),
            icon: const AppIcon(AppIcons.sort),
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
              icon: AppIcons.album,
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
          icon: AppIcons.error,
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
    final cachedArt = ref
        .watch(artistAlbumArtProvider)
        .getAlbumArt(album, artistName: artist);
    final hasImage = cachedArt != null && File(cachedArt).existsSync();

    if (!hasImage) {
      PassiveArtFetcherService.instance.fetchAlbumArtIfNeeded(album, artist);
    }

    final Widget artworkWidget = hasImage
        ? ClipRRect(
            borderRadius: AppTokens.brSm,
            child: Image.file(
              File(cachedArt),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          )
        : FolderGridImage(songs: songs, isGridItem: true);

    return GestureDetector(
      onLongPress: () => _showAlbumOptions(context, album, artist, songs),
      child: AppMediaCard(
        expand: true,
        title: album,
        subtitle: '$artist · ${collectionSummary(songs)}',
        artwork: artworkWidget,
        onTap: () => context.pushApp(SongListScreen(
          title: album,
          songs: songs,
          isAlbum: true,
          albumName: album,
          artistName: artist,
        )),
      ),
    );
  }

  void _showAlbumOptions(
      BuildContext context, String album, String artist, List<Song> songs) {
    showAppSheet(
      context,
      title: album,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.manageSearch,
            label: 'Fetch Missing Metadata',
            onTap: () {
              Navigator.pop(sheetContext);
              songActionFetchMissingMetadataForList(context, ref, songs);
            },
          ),
          AppSheetAction(
            icon: AppIcons.imageSearch,
            label: 'Change Album Artwork',
            onTap: () {
              Navigator.pop(sheetContext);
              _showChangeAlbumArtworkDialog(context, album, artist, songs);
            },
          ),
          AppSheetAction(
            icon: AppIcons.play,
            label: 'View Songs',
            onTap: () {
              Navigator.pop(sheetContext);
              context.pushApp(SongListScreen(title: album, songs: songs));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeAlbumArtworkDialog(
    BuildContext context,
    String album,
    String artist,
    List<Song> songs,
  ) async {
    appSnack(context, 'Searching online for $album artwork...');
    final onlineService = OnlineMetadataService.instance;
    final compositeKey = artist.isNotEmpty ? '$artist|$album' : album;

    final results = <Map<String, String>>[];

    try {
      final lastfmImage =
          await onlineService.searchLastfmAlbumImage(album, artistName: artist);
      if (lastfmImage != null && lastfmImage.isNotEmpty) {
        results.add({'url': lastfmImage, 'source': 'Last.fm'});
      }

      final iTunesImage =
          await onlineService.searchITunesAlbumImage(album, artistName: artist);
      if (iTunesImage != null &&
          iTunesImage.isNotEmpty &&
          iTunesImage != lastfmImage) {
        results.add({'url': iTunesImage, 'source': 'iTunes'});
      }

      final deezerImage =
          await onlineService.searchDeezerAlbumImage(album, artistName: artist);
      if (deezerImage != null &&
          deezerImage.isNotEmpty &&
          deezerImage != lastfmImage &&
          deezerImage != iTunesImage) {
        results.add({'url': deezerImage, 'source': 'Deezer'});
      }
    } catch (_) {}

    if (!context.mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Select Artwork for $album'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const AppIcon(AppIcons.musicNote),
                title: const Text('Use Song Cover Grid'),
                subtitle: const Text('Remove custom artwork'),
                onTap: () => Navigator.pop(dialogContext, 'reset'),
              ),
              if (results.isNotEmpty) const Divider(),
              ...results.map((res) => ListTile(
                    leading: Image.network(
                      res['url']!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const AppIcon(AppIcons.image),
                    ),
                    title: Text('Artwork from ${res['source']}'),
                    subtitle: Text(res['url']!,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(dialogContext, res['url']),
                  )),
              if (results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No online artwork options found'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null) return;

    if (selected == 'reset') {
      await ref
          .read(artistAlbumArtProvider.notifier)
          .removeAlbumArt(compositeKey);
      if (context.mounted) appSnack(context, 'Reset to song cover grid');
      return;
    }

    if (!context.mounted) return;
    appSnack(context, 'Downloading artwork...');
    final localPath = await onlineService.downloadAndCacheCover(
      selected,
      'album_$compositeKey',
    );

    if (localPath != null && context.mounted) {
      await ref.read(artistAlbumArtProvider.notifier).setAlbumArt(
            albumKey: compositeKey,
            albumName: album,
            artistName: artist,
            localPath: localPath,
            imageUrl: selected,
            source: 'online',
          );
      if (!context.mounted) return;
      appSnack(context, 'Updated artwork for $album');
    } else if (context.mounted) {
      appSnack(context, 'Failed to download artwork');
    }
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
      case 'name':
        albums.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case 'songs':
      default:
        albums.sort((a, b) {
          final countCompare =
              albumMap[b]!.length.compareTo(albumMap[a]!.length);
          if (countCompare != 0) return countCompare;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
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
          _sortAction(sheetContext, 'songs', AppIcons.musicNote, 'Most Songs'),
          _sortAction(sheetContext, 'name', AppIcons.sort, 'Name (A-Z)'),
          _sortAction(sheetContext, 'artist', AppIcons.person, 'Artist'),
        ],
      ),
    );
  }

  Widget _sortAction(
    BuildContext sheetContext,
    String value,
    AppIconData icon,
    String label,
  ) {
    final selected = _sortBy == value;
    return AppSheetAction(
      icon: icon,
      label: label,
      trailing: selected
          ? AppIcon(AppIcons.tick, color: AppTokens.accentOf(context, ref))
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(sheetContext);
      },
    );
  }
}

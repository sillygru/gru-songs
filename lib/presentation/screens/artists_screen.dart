import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

/// Returns true if [songArtist] matches [targetArtist] accounting for multi-artist strings.
bool _artistMatches(String songArtist, String targetArtist) {
  if (songArtist.isEmpty && targetArtist.isEmpty) return true;
  if (songArtist.isEmpty || targetArtist.isEmpty) return false;

  final parsedSongArtists = LibraryLogic.splitArtistNames(songArtist);
  if (parsedSongArtists.isEmpty) {
    return songArtist.trim().toLowerCase() == targetArtist.trim().toLowerCase();
  }

  final lowerTarget = targetArtist.trim().toLowerCase();
  return parsedSongArtists.any((artist) => artist.toLowerCase() == lowerTarget);
}

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  String _sortBy = 'songs'; // 'songs', 'name', 'recent'
  String _searchQuery = '';
  bool _isSearching = false;
  bool _hasTriggeredFetch = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);

    final songsValue = songsAsync.value;
    if (songsValue != null && !_hasTriggeredFetch) {
      _hasTriggeredFetch = true;
      final artistMap = LibraryLogic.groupByArtist(songsValue);
      for (final artist in artistMap.keys) {
        PassiveArtFetcherService.instance.fetchArtistArtIfNeeded(artist);
      }
    }

    return AmbientScaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search artists...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Artists'),
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
          var artistMap = LibraryLogic.groupByArtist(songs);

          if (_searchQuery.isNotEmpty) {
            artistMap = Map.fromEntries(
              artistMap.entries.where((entry) =>
                  entry.key.toLowerCase().contains(_searchQuery.toLowerCase())),
            );
          }

          final sortedArtists = _sortArtists(artistMap);

          if (sortedArtists.isEmpty) {
            return const AppEmptyState(
              icon: AppIcons.person,
              title: 'No artists found',
              message: 'Add music to your library to see artists.',
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
            itemCount: sortedArtists.length,
            itemBuilder: (context, index) {
              final artist = sortedArtists[index];
              final artistSongs = artistMap[artist]!;

              return _buildArtistCard(
                context,
                artist: artist,
                songs: artistSongs,
              );
            },
          );
        },
        loading: () => const AppLoading(),
        error: (e, _) => AppEmptyState(
          icon: AppIcons.error,
          title: 'Could not load artists',
          message: '$e',
          tone: AppTone.danger,
        ),
      ),
    );
  }

  Widget _buildArtistCard(
    BuildContext context, {
    required String artist,
    required List<Song> songs,
  }) {
    final cachedArt = ref.watch(artistAlbumArtProvider).getArtistArt(artist);
    final hasImage = cachedArt != null && File(cachedArt).existsSync();

    if (!hasImage) {
      PassiveArtFetcherService.instance.fetchArtistArtIfNeeded(artist);
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
      onLongPress: () => _showArtistOptions(context, artist, songs),
      child: AppMediaCard(
        expand: true,
        title: artist,
        subtitle: collectionSummary(songs),
        artwork: artworkWidget,
        onTap: () {
          final allSongs = ref.read(songsProvider).value ?? [];
          final artistSongs = allSongs.where((s) {
            final songArtist = s.artist.isEmpty ? 'Unknown Artist' : s.artist;
            return _artistMatches(songArtist, artist);
          }).toList();
          context.pushApp(SongListScreen(
            title: artist,
            songs: artistSongs,
            isArtist: true,
            artistName: artist,
          ));
        },
      ),
    );
  }

  void _showArtistOptions(
      BuildContext context, String artist, List<Song> songs) {
    showAppSheet(
      context,
      title: artist,
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
            label: 'Change Artist Artwork',
            onTap: () {
              Navigator.pop(sheetContext);
              _showChangeArtistArtworkDialog(context, artist, songs);
            },
          ),
          AppSheetAction(
            icon: AppIcons.play,
            label: 'View Songs',
            onTap: () {
              Navigator.pop(sheetContext);
              final allSongs = ref.read(songsProvider).value ?? [];
              final artistSongs = allSongs.where((s) {
                final songArtist =
                    s.artist.isEmpty ? 'Unknown Artist' : s.artist;
                return _artistMatches(songArtist, artist);
              }).toList();
              context
                  .pushApp(SongListScreen(title: artist, songs: artistSongs));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeArtistArtworkDialog(
    BuildContext context,
    String artist,
    List<Song> songs,
  ) async {
    appSnack(context, 'Searching online for $artist artwork...');
    final onlineService = OnlineMetadataService.instance;

    final results = <Map<String, String>>[];

    try {
      final lastfmImage = await onlineService.searchLastfmArtistImage(artist);
      if (lastfmImage != null && lastfmImage.isNotEmpty) {
        results.add({'url': lastfmImage, 'source': 'Last.fm'});
      }

      final iTunesImage = await onlineService.searchITunesArtistImage(artist);
      if (iTunesImage != null &&
          iTunesImage.isNotEmpty &&
          iTunesImage != lastfmImage) {
        results.add({'url': iTunesImage, 'source': 'iTunes'});
      }

      final deezerImage = await onlineService.searchDeezerArtistImage(artist);
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
        title: Text('Select Artwork for $artist'),
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
              ListTile(
                leading: const AppIcon(AppIcons.image),
                title: const Text('Choose Custom Image'),
                subtitle: const Text('Select image from device storage'),
                onTap: () => Navigator.pop(dialogContext, 'custom'),
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
      await ref.read(artistAlbumArtProvider.notifier).removeArtistArt(artist);
      if (context.mounted) appSnack(context, 'Reset to song cover grid');
      return;
    }

    if (selected == 'custom') {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (picked != null && picked.files.single.path != null) {
        final localPath = picked.files.single.path!;
        await ref.read(artistAlbumArtProvider.notifier).setArtistArt(
              artistName: artist,
              localPath: localPath,
              source: 'custom',
            );
        if (context.mounted) {
          appSnack(context, 'Updated artwork for $artist');
        }
      }
      return;
    }

    if (!context.mounted) return;
    appSnack(context, 'Downloading artwork...');
    final localPath = await onlineService.downloadAndCacheCover(
      selected,
      'artist_$artist',
    );

    if (localPath != null && context.mounted) {
      await ref.read(artistAlbumArtProvider.notifier).setArtistArt(
            artistName: artist,
            localPath: localPath,
            imageUrl: selected,
            source: 'online',
          );
      if (!context.mounted) return;
      appSnack(context, 'Updated artwork for $artist');
    } else if (context.mounted) {
      appSnack(context, 'Failed to download artwork');
    }
  }

  List<String> _sortArtists(Map<String, List<Song>> artistMap) {
    final artists = artistMap.keys.toList();

    switch (_sortBy) {
      case 'name':
        artists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case 'songs':
      default:
        artists.sort((a, b) {
          final countCompare =
              artistMap[b]!.length.compareTo(artistMap[a]!.length);
          if (countCompare != 0) return countCompare;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
    }

    return artists;
  }

  void _showSortOptions(BuildContext context) {
    showAppSheet(
      context,
      title: 'Sort artists',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortAction(sheetContext, 'songs', AppIcons.musicNote, 'Most Songs'),
          _sortAction(sheetContext, 'name', AppIcons.sort, 'Name (A-Z)'),
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

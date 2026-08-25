import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/artist_album_art_provider.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../../services/online_metadata_service.dart';
import '../../services/passive_art_fetcher_service.dart';
import '../components/ambient_scaffold.dart';
import '../components/app_dialog.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../components/app_screen_header.dart';
import '../components/app_sheet.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';
import '../widgets/bulk_selection_bar.dart';
import '../widgets/duration_display.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/sort_menu.dart';
import '../components/song_actions.dart';
import 'select_songs_screen.dart';

class SongListScreen extends ConsumerWidget {
  final String title;
  final List<Song> songs;
  final String? playlistId;
  final bool isArtist;
  final bool isAlbum;
  final String? artistName;
  final String? albumName;

  const SongListScreen({
    super.key,
    required this.title,
    required this.songs,
    this.playlistId,
    this.isArtist = false,
    this.isAlbum = false,
    this.artistName,
    this.albumName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final selectionState = ref.watch(selectionProvider);
    final sortOrder = ref.watch(settingsProvider).sortOrder;
    final userData = ref.watch(userDataProvider);
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider);
    final lastPlayedAsync = ref.watch(lastPlayedTimestampsProvider);
    final lastPlayedTimestamps = lastPlayedAsync.asData?.value ?? const {};

    final sortedSongs = LibraryLogic.sortSongs(
      songs,
      sortOrder,
      userData: userData,
      shuffleConfig: shuffleConfig,
      playCounts: playCounts,
      lastPlayedTimestamps: lastPlayedTimestamps,
    );

    final bool canFetchCover = playlistId == null;

    final bool effectiveIsArtist = isArtist ||
        (playlistId == null &&
            !isAlbum &&
            sortedSongs.isNotEmpty &&
            sortedSongs.any(
              (s) =>
                  s.artist.toLowerCase().contains(title.toLowerCase()) ||
                  title.toLowerCase().contains(s.artist.toLowerCase()),
            ));

    final bool effectiveIsAlbum = isAlbum ||
        (playlistId == null &&
            !effectiveIsArtist &&
            sortedSongs.isNotEmpty &&
            sortedSongs.any(
              (s) =>
                  s.album.toLowerCase().contains(title.toLowerCase()) ||
                  title.toLowerCase().contains(s.album.toLowerCase()),
            ));

    final String effectiveArtistName = (artistName ??
            (effectiveIsArtist
                ? title
                : (sortedSongs.isNotEmpty ? sortedSongs.first.artist : '')))
        .trim();

    final String effectiveAlbumName = (albumName ??
            (effectiveIsAlbum
                ? title
                : (sortedSongs.isNotEmpty ? sortedSongs.first.album : title)))
        .trim();

    final String? artworkPath = effectiveIsArtist
        ? ref.watch(artistAlbumArtProvider).getArtistArt(effectiveArtistName)
        : (effectiveIsAlbum
            ? ref.watch(artistAlbumArtProvider).getAlbumArt(
                  effectiveAlbumName,
                  artistName: effectiveArtistName,
                )
            : null);

    final bool hasCustomArtwork =
        artworkPath != null && File(artworkPath).existsSync();

    if (effectiveIsArtist && !hasCustomArtwork) {
      PassiveArtFetcherService.instance.fetchArtistArtIfNeeded(
        effectiveArtistName,
      );
    } else if (effectiveIsAlbum && !hasCustomArtwork) {
      PassiveArtFetcherService.instance.fetchAlbumArtIfNeeded(
        effectiveAlbumName,
        effectiveArtistName,
      );
    }

    void handleFetchCover() {
      if (effectiveIsArtist) {
        _showChangeArtistArtworkDialog(
          context,
          ref,
          effectiveArtistName,
          sortedSongs,
        );
      } else if (effectiveIsAlbum) {
        _showChangeAlbumArtworkDialog(
          context,
          ref,
          effectiveAlbumName,
          effectiveArtistName,
          sortedSongs,
        );
      } else {
        _showChangeArtistArtworkDialog(context, ref, title, sortedSongs);
      }
    }

    final bool isUnknownArtistOrAlbum = (effectiveIsArtist &&
            OnlineMetadataService.cleanTag(effectiveArtistName) == null) ||
        (effectiveIsAlbum &&
            OnlineMetadataService.cleanTag(effectiveAlbumName) == null) ||
        title.toLowerCase() == 'unknown artist' ||
        title.toLowerCase() == 'unknown album';

    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selectionState.isSelectionMode) {
          ref.read(selectionProvider.notifier).exitSelectionMode();
        }
      },
      child: AmbientScaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader(
              title: title,
              large: false,
              floating: true,
              snap: true,
              actions: [
                const SortMenu(),
                if (isUnknownArtistOrAlbum)
                  IconButton(
                    icon: const AppIcon(AppIcons.manageSearch),
                    onPressed: () => songActionFetchMissingMetadataForList(
                      context,
                      ref,
                      sortedSongs,
                    ),
                    tooltip: 'Fetch Missing Metadata',
                  )
                else if (canFetchCover)
                  IconButton(
                    icon: const AppIcon(AppIcons.imageSearch),
                    onPressed: handleFetchCover,
                    tooltip: effectiveIsArtist
                        ? 'Fetch Artist Cover Online'
                        : (effectiveIsAlbum
                            ? 'Fetch Album Cover Online'
                            : 'Fetch Cover Online'),
                  ),
                if (playlistId != null)
                  IconButton(
                    icon: const AppIcon(AppIcons.moreVert),
                    onPressed: () => _showPlaylistOptions(context, ref),
                    tooltip: 'Playlist Options',
                  ),
                if (playlistId == null &&
                    !effectiveIsArtist &&
                    !effectiveIsAlbum &&
                    sortedSongs.length >= 2)
                  IconButton(
                    icon: const AppIcon(AppIcons.merge),
                    onPressed: () async {
                      final result =
                          await context.pushApp<Map<String, dynamic>>(
                        SelectSongsScreen(
                          songs: sortedSongs,
                          title: 'Select Songs to Merge',
                        ),
                      );
                      if (result != null && context.mounted) {
                        final selected = result['filenames'] as List<String>;
                        final priority = result['priority'] as String?;
                        if (selected.length >= 2) {
                          try {
                            await ref
                                .read(userDataProvider.notifier)
                                .createMergedGroup(
                                  selected,
                                  priorityFilename: priority,
                                );
                            if (context.mounted) {
                              appSnack(
                                context,
                                'Merged ${selected.length} songs',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              appSnack(context, 'Error: $e');
                            }
                          }
                        }
                      }
                    },
                    tooltip: 'Merge Songs',
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: canFetchCover ? handleFetchCover : null,
                      onLongPress: canFetchCover ? handleFetchCover : null,
                      child: Center(
                        child: SizedBox(
                          width: 220,
                          height: 220,
                          child: ClipRRect(
                            borderRadius: AppTokens.brMd,
                            child: hasCustomArtwork
                                ? Image.file(
                                    File(artworkPath),
                                    width: 220,
                                    height: 220,
                                    cacheWidth: 550,
                                    cacheHeight: 550,
                                    fit: BoxFit.cover,
                                  )
                                : FolderGridImage(
                                    songs: sortedSongs,
                                    size: 220,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onLongPress: playlistId != null
                          ? () => _showRenameDialog(context, ref)
                          : null,
                      child: Text(
                        title,
                        style: AppTokens.screenTitle(context),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s2),
                    if (sortedSongs.isNotEmpty)
                      CollectionDurationDisplay(
                        songs: sortedSongs,
                        showSongCount: true,
                        compact: true,
                        style: AppTokens.meta(context),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: sortedSongs.isNotEmpty
                              ? () {
                                  audioManager.shuffleAndPlay(
                                    sortedSongs,
                                    isRestricted: true,
                                  );
                                }
                              : null,
                          icon: const AppIcon(AppIcons.shuffle),
                          label: const Text('Shuffle'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: sortedSongs.isNotEmpty
                              ? () {
                                  audioManager.replaceQueue(
                                    sortedSongs,
                                    playlistId: playlistId,
                                    forceLinear: true,
                                    clearCurrentSong: true,
                                  );
                                }
                              : null,
                          icon: const AppIcon(AppIcons.play),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isUnknownArtistOrAlbum) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: sortedSongs.isNotEmpty
                            ? () => songActionFetchMissingMetadataForList(
                                  context,
                                  ref,
                                  sortedSongs,
                                )
                            : null,
                        icon: const AppIcon(AppIcons.manageSearch),
                        label: const Text('Fetch Missing Metadata'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            if (sortedSongs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: AppIcons.musicNote,
                  title: 'No songs in this list',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = sortedSongs[index];

                  return SongListItem(
                    song: song,
                    heroTagPrefix: 'song_list_$title',
                    playlistId: playlistId,
                    onTap: () {
                      audioManager.playSong(
                        song,
                        contextQueue: sortedSongs,
                        playlistId: playlistId,
                      );
                    },
                  );
                }, childCount: sortedSongs.length),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
        bottomNavigationBar:
            selectionState.isSelectionMode ? const BulkSelectionBar() : null,
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, WidgetRef ref) {
    if (playlistId == null) return;

    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.edit,
            label: 'Rename',
            onTap: () {
              Navigator.pop(sheetContext);
              _showRenameDialog(context, ref);
            },
          ),
          AppSheetAction(
            icon: AppIcons.delete,
            label: 'Delete',
            isDanger: true,
            onTap: () {
              Navigator.pop(sheetContext);
              _showDeleteConfirmation(context, ref);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    if (playlistId == null) return;

    final newName = await showAppTextPrompt(
      context,
      title: 'Rename Playlist',
      initialValue: title,
      confirmLabel: 'Rename',
    );
    if (newName != null && newName != title) {
      ref
          .read(userDataProvider.notifier)
          .updatePlaylistName(playlistId!, newName);
    }
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (playlistId == null) return;

    final confirmed = await showAppConfirm(
      context,
      title: 'Delete Playlist',
      message: 'Are you sure you want to delete "$title"?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (confirmed == true && context.mounted) {
      ref.read(userDataProvider.notifier).deletePlaylist(playlistId!);
      Navigator.pop(context);
    }
  }

  Future<void> _showChangeArtistArtworkDialog(
    BuildContext context,
    WidgetRef ref,
    String artist,
    List<Song> songs,
  ) async {
    appSnack(context, 'Searching online for $artist artwork...');
    final onlineService = OnlineMetadataService.instance;

    final results = <Map<String, String>>[];

    try {
      results.addAll(await onlineService.searchArtistImageCandidates(artist));
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
              ...results.map(
                (res) => ListTile(
                  leading: Image.network(
                    res['url']!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const AppIcon(AppIcons.image),
                  ),
                  title: Text('Artwork from ${res['source']}'),
                  subtitle: Text(
                    res['url']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(dialogContext, res['url']),
                ),
              ),
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

    if (context.mounted) appSnack(context, 'Downloading artwork...');
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
      if (context.mounted) {
        appSnack(context, 'Updated artwork for $artist');
      }
    } else if (context.mounted) {
      appSnack(context, 'Failed to download artwork');
    }
  }

  Future<void> _showChangeAlbumArtworkDialog(
    BuildContext context,
    WidgetRef ref,
    String album,
    String artist,
    List<Song> songs,
  ) async {
    appSnack(context, 'Searching online for $album artwork...');
    final onlineService = OnlineMetadataService.instance;
    final compositeKey = artist.isNotEmpty ? '$artist|$album' : album;

    final results = <Map<String, String>>[];

    try {
      results.addAll(
        await onlineService.searchAlbumImageCandidates(
          album,
          artistName: artist,
        ),
      );
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
              ListTile(
                leading: const AppIcon(AppIcons.image),
                title: const Text('Choose Custom Image'),
                subtitle: const Text('Select image from device storage'),
                onTap: () => Navigator.pop(dialogContext, 'custom'),
              ),
              if (results.isNotEmpty) const Divider(),
              ...results.map(
                (res) => ListTile(
                  leading: Image.network(
                    res['url']!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const AppIcon(AppIcons.image),
                  ),
                  title: Text('Artwork from ${res['source']}'),
                  subtitle: Text(
                    res['url']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(dialogContext, res['url']),
                ),
              ),
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

    if (selected == 'custom') {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (picked != null && picked.files.single.path != null) {
        final localPath = picked.files.single.path!;
        await ref.read(artistAlbumArtProvider.notifier).setAlbumArt(
              albumKey: compositeKey,
              albumName: album,
              artistName: artist.isNotEmpty ? artist : null,
              localPath: localPath,
              source: 'custom',
            );
        if (context.mounted) {
          appSnack(context, 'Updated artwork for $album');
        }
      }
      return;
    }

    if (context.mounted) appSnack(context, 'Downloading artwork...');
    final localPath = await onlineService.downloadAndCacheCover(
      selected,
      'album_$compositeKey',
    );

    if (localPath != null && context.mounted) {
      await ref.read(artistAlbumArtProvider.notifier).setAlbumArt(
            albumKey: compositeKey,
            albumName: album,
            artistName: artist.isNotEmpty ? artist : null,
            localPath: localPath,
            imageUrl: selected,
            source: 'online',
          );
      if (context.mounted) {
        appSnack(context, 'Updated artwork for $album');
      }
    } else if (context.mounted) {
      appSnack(context, 'Failed to download artwork');
    }
  }
}

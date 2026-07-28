import 'dart:io';
import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../models/shuffle_config.dart';
import '../../providers/artist_album_art_provider.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../services/audio_player_manager.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_options_menu.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/sort_menu.dart';
import '../widgets/duration_display.dart';
import '../components/app_feedback.dart';
import '../components/app_list_row.dart';
import '../components/app_media_card.dart';
import '../components/app_screen_header.dart';
import '../components/scroll_chrome.dart';
import '../components/app_segmented_tabs.dart';
import '../components/app_sheet.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';
import 'merged_songs_screen.dart';
import 'select_songs_screen.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final String? relativePath;
  final ScrollController? scrollController;
  final int initialTabIndex;

  const LibraryScreen({
    super.key,
    this.relativePath,
    this.scrollController,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with ScrollChromeMixin {
  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
    final rootPathAsync = ref.watch(libraryRootPathProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final settings = ref.watch(settingsProvider);
    final sortOrder = settings.sortOrder;
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider);
    final lastPlayedAsync = ref.watch(lastPlayedTimestampsProvider);
    final lastPlayedTimestamps = lastPlayedAsync.asData?.value ?? const {};
    final isRoot = widget.relativePath == null;

    // The folder tab needs both the library and the folder it is rooted at, so
    // it stays on the loading state until both are known — never on an "empty"
    // one that reads as "you have no music".
    Widget buildFolderTab() {
      return songsAsyncValue.when(
        data: (allSongs) => rootPathAsync.when(
          data: (musicRoot) {
            if (musicRoot == null) {
              return const AppEmptyState(
                icon: AppIcons.folderOff,
                title: 'No music folder yet',
                message: 'Select a music folder in Home to fill this out.',
              );
            }
            return _buildFolderView(
              context,
              musicRoot,
              allSongs,
              userData,
              audioManager,
              sortOrder,
              shuffleConfig,
              lastPlayedTimestamps,
              playCounts,
            );
          },
          loading: () => const AppLoading(),
          error: (e, s) => AppEmptyState(
            icon: AppIcons.error,
            title: 'Could not find your music folder',
            message: '$e',
            tone: AppTone.danger,
          ),
        ),
        loading: () => const AppLoading(),
        error: (e, s) => AppEmptyState(
          icon: AppIcons.error,
          title: isRoot ? 'Could not load library' : 'Could not open folder',
          message: '$e',
          tone: AppTone.danger,
        ),
      );
    }

    if (!isRoot) {
      // Sub-folder screens own their own scaffold once content is available;
      // until then they still need chrome to hang the loading state on.
      final hasContent = songsAsyncValue.hasValue &&
          rootPathAsync.hasValue &&
          rootPathAsync.value != null;
      if (hasContent) return buildFolderTab();

      return AmbientScaffold(
        appBar: AppTopBar(title: widget.relativePath ?? 'Library'),
        body: buildFolderTab(),
      );
    }

    final navIntent = ref.watch(libraryNavigationProvider);
    final initialTabIndex =
        (navIntent?.subTabIndex ?? widget.initialTabIndex).clamp(0, 2);

    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Builder(
        builder: (context) {
          ref.listen(libraryNavigationProvider, (previous, next) {
            if (next == null) return;
            final controller = DefaultTabController.of(context);
            if (controller.index != next.subTabIndex) {
              controller.animateTo(next.subTabIndex);
            }
          });

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: NestedScrollView(
              controller: widget.scrollController,
              // Required for the header's snap to work over the tab body —
              // without it the outer scroll won't float the sliver back in.
              floatHeaderSlivers: true,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  AppSliverHeader(
                    title: 'Library',
                    isScrolled: innerBoxIsScrolled,
                    floating: true,
                    snap: true,
                    actions: [
                      songsAsyncValue.when(
                        data: (songs) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SortMenu(),
                            IconButton(
                              icon: const AppIcon(AppIcons.shuffle),
                              tooltip: 'Shuffle all',
                              onPressed: () {
                                if (songs.isNotEmpty) {
                                  audioManager.shuffleAndPlay(songs,
                                      isRestricted: false);
                                }
                              },
                            ),
                          ],
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                    bottom: AppSegmentedTabs(
                      controller: DefaultTabController.of(context),
                      labels: const ['Folders', 'Artists', 'Albums'],
                      accent: AppTokens.accentOf(context, ref),
                    ),
                  ),
                ];
              },
              body: songsAsyncValue.when(
                data: (allSongs) => TabBarView(
                  children: [
                    buildFolderTab(),
                    _buildArtistsView(context, allSongs),
                    _buildAlbumsView(context, allSongs),
                  ],
                ),
                loading: () => const AppLoading(),
                error: (e, s) => AppEmptyState(
                  icon: AppIcons.error,
                  title: 'Could not load library',
                  message: '$e',
                  tone: AppTone.danger,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFolderView(
    BuildContext context,
    String musicRoot,
    List<Song> allSongs,
    UserDataState userData,
    AudioPlayerManager audioManager,
    SongSortOrder sortOrder,
    ShuffleConfig shuffleConfig,
    Map<String, double> lastPlayedTimestamps,
    Map<String, int> playCounts,
  ) {
    final currentFullPath = widget.relativePath == null
        ? musicRoot
        : p.join(musicRoot, widget.relativePath);

    final content = LibraryLogic.getFolderContent(
      allSongs: allSongs,
      currentFullPath: currentFullPath,
      sortOrder: sortOrder,
      userData: userData,
      shuffleConfig: shuffleConfig,
      playCounts: playCounts,
      lastPlayedTimestamps: lastPlayedTimestamps,
      affinities: ref.watch(songAffinitiesProvider).asData?.value,
    );

    final sortedSubFolders = content.subFolders;
    final immediateSongs = content.immediateSongs;
    final isRoot = widget.relativePath == null;
    final playlists =
        userData.playlists.where((p) => !p.isRecommendation).toList();

    Widget folderIndexBuilder(BuildContext context, int index) {
      int offset = 0;

      // 1. Favorites Folder (at root only)
      if (isRoot) {
        if (index == 0) {
          final favSongs =
              allSongs.where((s) => userData.isFavorite(s.filename)).toList();

          return AppListRow(
            leading: const AppRowIcon(
              icon: AppIcons.favorite,
              color: AppTokens.danger,
            ),
            title: 'Favorites',
            subtitleWidget: CollectionDurationDisplay(
              songs: favSongs,
              showSongCount: true,
              compact: true,
            ),
            onTap: () {
              context.pushApp(
                SongListScreen(title: 'Favorites', songs: favSongs),
              );
            },
          );
        }
        offset = 1;

        // 2. Merged Songs Folder (at root only)
        if (index == 1) {
          final mergedCount = userData.mergedGroups.length;

          return AppListRow(
            leading: AppRowIcon(
              icon: AppIcons.merge,
              color: AppTokens.accentOf(context, ref),
            ),
            title: 'Merged Songs',
            subtitle: '$mergedCount group${mergedCount != 1 ? 's' : ''}',
            trailing: IconButton(
              icon: const AppIcon(AppIcons.add),
              tooltip: 'Create new merge group',
              onPressed: () async {
                final result = await context.pushApp<Map<String, dynamic>>(
                  SelectSongsScreen(
                    songs: allSongs,
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
                          .createMergedGroup(selected,
                              priorityFilename: priority);
                      if (context.mounted) {
                        appSnack(
                          context,
                          'Merged ${selected.length} songs',
                          tone: AppTone.success,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        appSnack(context, '$e', tone: AppTone.danger);
                      }
                    }
                  }
                }
              },
            ),
            onTap: () {
              context.pushApp(const MergedSongsScreen());
            },
          );
        }
        offset = 2;

        // 3. Playlists (at root only)
        if (index - offset < playlists.length) {
          final playlist = playlists[index - offset];
          final playlistSongs = allSongs
              .where((s) =>
                  playlist.songs.any((ps) => ps.songFilename == s.filename))
              .toList();

          // The playlist used to be marked by a 2px accent ring; the
          // collage now stands on its own.
          return AppListRow(
            leading: AppRowArt(
              child: FolderGridImage(songs: playlistSongs),
            ),
            title: playlist.name,
            subtitleWidget: CollectionDurationDisplay(
              songs: playlistSongs,
              showSongCount: true,
              compact: true,
            ),
            trailing: IconButton(
              icon: const AppIcon(AppIcons.moreVert),
              tooltip: 'Playlist options',
              onPressed: () {
                showAppSheet(
                  context,
                  title: playlist.name,
                  builder: (sheetContext) => AppSheetAction(
                    icon: AppIcons.delete,
                    label: 'Delete playlist',
                    isDanger: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ref
                          .read(userDataProvider.notifier)
                          .deletePlaylist(playlist.id);
                    },
                  ),
                );
              },
            ),
            onTap: () {
              context.pushApp(
                SongListScreen(
                  title: playlist.name,
                  songs: playlistSongs,
                  playlistId: playlist.id,
                ),
              );
            },
          );
        }
        offset += playlists.length;
      }

      final folderIndex = index - offset;
      if (folderIndex < sortedSubFolders.length) {
        final folderName = sortedSubFolders[folderIndex];
        final folderRelativePath = widget.relativePath == null
            ? folderName
            : p.join(widget.relativePath!, folderName);
        final folderSongs = content.subFolderSongs[folderName] ?? [];

        return AppListRow(
          leading: AppRowArt(child: FolderGridImage(songs: folderSongs)),
          title: folderName,
          subtitleWidget: CollectionDurationDisplay(
            songs: folderSongs,
            showSongCount: true,
            compact: true,
          ),
          trailing: IconButton(
            icon: const AppIcon(AppIcons.moreVert),
            tooltip: 'Folder options',
            onPressed: () {
              // Absolute, because the tree root is not necessarily the
              // first configured music folder any more.
              showFolderOptionsMenu(context, ref, folderName,
                  p.join(currentFullPath, folderName));
            },
          ),
          onTap: () {
            context.pushApp(LibraryScreen(relativePath: folderRelativePath));
          },
        );
      }

      final songIndex = folderIndex - sortedSubFolders.length;
      final song = immediateSongs[songIndex];

      return SongListItem(
        song: song,
        heroTagPrefix: 'library_${widget.relativePath ?? 'root'}',
        onTap: () {
          audioManager.playSong(song, contextQueue: immediateSongs);
        },
      );
    }

    final itemCount = (isRoot ? (2 + playlists.length) : 0) +
        sortedSubFolders.length +
        immediateSongs.length;

    if (isRoot) {
      return NotificationListener<ScrollNotification>(
        onNotification: handleScrollNotification,
        child: ListView.builder(
          itemCount: itemCount,
          padding: const EdgeInsets.only(
            bottom: AppTokens.scrollBottomInset,
          ),
          itemBuilder: folderIndexBuilder,
        ),
      );
    } else {
      return AmbientScaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: handleScrollNotification,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              AppSliverHeader(
                title: widget.relativePath ?? 'Library',
                isScrolled: isScrolled,
                large: false,
                floating: true,
                snap: true,
                pinned: false,
                actions: [
                  const SortMenu(),
                  if (content.allSongsInFolder.isNotEmpty)
                    IconButton(
                      icon: const AppIcon(AppIcons.shuffle),
                      tooltip: 'Shuffle folder',
                      onPressed: () => audioManager.shuffleAndPlay(
                        content.allSongsInFolder,
                        isRestricted: true,
                      ),
                    ),
                ],
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  folderIndexBuilder,
                  childCount: itemCount,
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: AppTokens.scrollBottomInset),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildArtistsView(BuildContext context, List<Song> allSongs) {
    final artistsAsync = ref.watch(artistListProvider);

    return artistsAsync.when(
      data: (artists) {
        final artistMap = LibraryLogic.groupByArtist(allSongs);
        return _buildCollectionGrid(
          keys: artists,
          songsFor: (artist) => artistMap[artist] ?? const [],
          subtitleFor: collectionSummary,
          emptyTitle: 'No artists yet',
          isArtist: true,
        );
      },
      loading: () => const AppLoading(),
      error: (e, s) => AppEmptyState(
        icon: AppIcons.error,
        title: 'Could not load artists',
        message: '$e',
        tone: AppTone.danger,
      ),
    );
  }

  Widget _buildAlbumsView(BuildContext context, List<Song> allSongs) {
    final albumsAsync = ref.watch(albumListProvider);

    return albumsAsync.when(
      data: (albums) {
        final albumMap = LibraryLogic.groupByAlbum(allSongs);
        return _buildCollectionGrid(
          keys: albums,
          songsFor: (album) => albumMap[album] ?? const [],
          subtitleFor: (songs) =>
              '${songs.first.artist} · ${collectionSummary(songs)}',
          emptyTitle: 'No albums yet',
          isAlbum: true,
        );
      },
      loading: () => const AppLoading(),
      error: (e, s) => AppEmptyState(
        icon: AppIcons.error,
        title: 'Could not load albums',
        message: '$e',
        tone: AppTone.danger,
      ),
    );
  }

  /// Artists and Albums are the same grid of cover collages with different
  /// labels underneath, so they are the same code.
  Widget _buildCollectionGrid({
    required List<String> keys,
    required List<Song> Function(String) songsFor,
    required String Function(List<Song>) subtitleFor,
    required String emptyTitle,
    bool isArtist = false,
    bool isAlbum = false,
  }) {
    final entries = keys
        .map((key) => (key: key, songs: songsFor(key)))
        .where((entry) => entry.songs.isNotEmpty)
        .toList();

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.library,
        title: emptyTitle,
        message: 'Scan a music folder to fill this out.',
      );
    }

    final artState = ref.watch(artistAlbumArtProvider);
    final sortOrder = ref.watch(settingsProvider).sortOrder;
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider);
    final lastPlayedAsync = ref.watch(lastPlayedTimestampsProvider);
    final lastPlayedTimestamps = lastPlayedAsync.asData?.value ?? const {};

    return NotificationListener<ScrollNotification>(
      onNotification: handleScrollNotification,
      child: GridView.builder(
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
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final sortedEntrySongs = LibraryLogic.sortSongs(
            entry.songs,
            sortOrder,
            userData: userData,
            shuffleConfig: shuffleConfig,
            playCounts: playCounts,
            lastPlayedTimestamps: lastPlayedTimestamps,
          );
          final String? artistName = isArtist
              ? entry.key
              : (sortedEntrySongs.isNotEmpty
                  ? sortedEntrySongs.first.artist
                  : null);
          final String? albumName = isAlbum ? entry.key : null;

          final cachedArt = isArtist
              ? artState.getArtistArt(artistName)
              : (isAlbum
                  ? artState.getAlbumArt(albumName, artistName: artistName)
                  : null);
          final hasImage = cachedArt != null && File(cachedArt).existsSync();

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
              : FolderGridImage(songs: sortedEntrySongs, isGridItem: true);

          return AppMediaCard(
            expand: true,
            title: entry.key,
            subtitle: subtitleFor(entry.songs),
            artwork: artworkWidget,
            onTap: () => context.pushApp(
              SongListScreen(
                title: entry.key,
                songs: entry.songs,
                isArtist: isArtist,
                isAlbum: isAlbum,
                artistName: artistName,
                albumName: albumName,
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../models/shuffle_config.dart';
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
import '../components/app_sheet.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';
import 'merged_songs_screen.dart';
import 'select_songs_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final String? relativePath;
  final ScrollController? scrollController;

  const LibraryScreen({super.key, this.relativePath, this.scrollController});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const double _bottomDockDragDistance = 88.0;

  bool _isScrolled = false;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final scrolled = notification.metrics.pixels > 0;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta != 0) {
        ref.read(bottomDockVisibilityProvider.notifier).updateFromDrag(
              scrollDelta: delta,
              dragDistanceForFullToggle: _bottomDockDragDistance,
            );
      }
    } else if (notification is ScrollEndNotification) {
      ref.read(bottomDockVisibilityProvider.notifier).settle();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final settings = ref.watch(settingsProvider);
    final sortOrder = settings.sortOrder;
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider);
    final isRoot = widget.relativePath == null;

    if (!isRoot) {
      return songsAsyncValue.when(
        data: (allSongs) => _buildFolderView(
          context,
          allSongs,
          userData,
          audioManager,
          sortOrder,
          shuffleConfig,
          playCounts,
        ),
        loading: () => Scaffold(
          appBar: AppTopBar(title: widget.relativePath ?? 'Library'),
          body: const AppLoading(),
        ),
        error: (e, s) => Scaffold(
          appBar: AppTopBar(title: widget.relativePath ?? 'Library'),
          body: AppEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not open folder',
            message: '$e',
            tone: AppTone.danger,
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NestedScrollView(
          controller: widget.scrollController,
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
                          icon: const Icon(Icons.shuffle_rounded),
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
                // Indicator, label weights and the absent divider all come
                // from tabBarTheme now.
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Folders'),
                    Tab(text: 'Artists'),
                    Tab(text: 'Albums'),
                  ],
                ),
              ),
            ];
          },
          body: songsAsyncValue.when(
            data: (allSongs) => TabBarView(
              children: [
                _buildFolderView(
                  context,
                  allSongs,
                  userData,
                  audioManager,
                  sortOrder,
                  shuffleConfig,
                  playCounts,
                ),
                _buildArtistsView(context, allSongs),
                _buildAlbumsView(context, allSongs),
              ],
            ),
            loading: () => const AppLoading(),
            error: (e, s) => AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load library',
              message: '$e',
              tone: AppTone.danger,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderView(
    BuildContext context,
    List<Song> allSongs,
    UserDataState userData,
    AudioPlayerManager audioManager,
    SongSortOrder sortOrder,
    ShuffleConfig shuffleConfig,
    Map<String, int> playCounts,
  ) {
    return FutureBuilder<String?>(
      future: ref.read(storageServiceProvider).getMusicFolderPath(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(
              child: Text('Please select a music folder in Home first.'));
        }

        final musicRoot =
            Platform.isIOS ? p.normalize(snapshot.data!) : snapshot.data!;
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
              final favSongs = allSongs
                  .where((s) => userData.isFavorite(s.filename))
                  .toList();

              return AppListRow(
                leading: const AppRowIcon(
                  icon: Icons.favorite_rounded,
                  color: AppTokens.danger,
                ),
                title: 'Favorites',
                subtitleWidget: CollectionDurationDisplay(
                  songs: favSongs,
                  showSongCount: true,
                  compact: true,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SongListScreen(
                        title: 'Favorites',
                        songs: favSongs,
                      ),
                    ),
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
                  icon: Icons.merge_type_rounded,
                  color: AppTokens.accentOf(context, ref),
                ),
                title: 'Merged Songs',
                subtitle: '$mergedCount group${mergedCount != 1 ? 's' : ''}',
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Create new merge group',
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SelectSongsScreen(
                          songs: allSongs,
                          title: 'Select Songs to Merge',
                        ),
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MergedSongsScreen(),
                    ),
                  );
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
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: 'Playlist options',
                  onPressed: () {
                    showAppSheet(
                      context,
                      title: playlist.name,
                      builder: (sheetContext) => AppSheetAction(
                        icon: Icons.delete_outline_rounded,
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SongListScreen(
                        title: playlist.name,
                        songs: playlistSongs,
                        playlistId: playlist.id,
                      ),
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
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Folder options',
                onPressed: () {
                  showFolderOptionsMenu(
                      context, ref, folderName, folderRelativePath);
                },
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        LibraryScreen(relativePath: folderRelativePath),
                  ),
                );
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
            onNotification: _handleScrollNotification,
            child: ListView.builder(
              itemCount: itemCount,
              padding: const EdgeInsets.only(
                bottom: AppTokens.scrollBottomInset,
              ),
              itemBuilder: folderIndexBuilder,
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  AppSliverHeader(
                    title: widget.relativePath ?? 'Library',
                    isScrolled: _isScrolled,
                    large: false,
                    floating: true,
                    snap: true,
                    pinned: false,
                    actions: [
                      const SortMenu(),
                      if (content.allSongsInFolder.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.shuffle_rounded),
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
                    padding:
                        EdgeInsets.only(bottom: AppTokens.scrollBottomInset),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
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
        );
      },
      loading: () => const AppLoading(),
      error: (e, s) => AppEmptyState(
        icon: Icons.error_outline_rounded,
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
        );
      },
      loading: () => const AppLoading(),
      error: (e, s) => AppEmptyState(
        icon: Icons.error_outline_rounded,
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
  }) {
    final entries = keys
        .map((key) => (key: key, songs: songsFor(key)))
        .where((entry) => entry.songs.isNotEmpty)
        .toList();

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.library_music_rounded,
        title: emptyTitle,
        message: 'Scan a music folder to fill this out.',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
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

          return AppMediaCard(
            expand: true,
            title: entry.key,
            subtitle: subtitleFor(entry.songs),
            artwork: FolderGridImage(songs: entry.songs, isGridItem: true),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: entry.key,
                  songs: entry.songs,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

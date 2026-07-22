import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/album_art_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../../models/song.dart';
import '../../models/queue_snapshot.dart';
import '../../services/audio_player_manager.dart';
import '../../providers/queue_history_provider.dart';
import '../../providers/mixed_playlists_provider.dart';
import '../../providers/auto_mood_mix_provider.dart';
import '../../models/playlist.dart';
import 'song_list_screen.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/sort_menu.dart';
import 'search_screen.dart';
import 'unified_player_screen.dart';
import '../routes/player_route.dart';
import '../components/app_dialog.dart';
import '../components/app_feedback.dart';
import '../components/app_media_card.dart';
import '../components/app_screen_header.dart';
import '../components/app_section_header.dart';
import '../components/app_sheet.dart';
import '../components/app_surface.dart';
import '../tokens/app_tokens.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const HomeScreen({super.key, this.scrollController});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _bottomDockDragDistance = 88.0;
  static const double _cardSize = 168;
  static const double _queueCardSize = 120;

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

  Future<void> _selectMusicFolder() async {
    final storage = ref.read(storageServiceProvider);
    final selection = await storage.pickMusicFolder();
    if (selection == null || selection['path']!.isEmpty) {
      if (mounted) {
        appSnack(context, 'Unable to access selected folder',
            tone: AppTone.danger);
      }
      return;
    }

    await storage.addMusicFolder(
      selection['path']!,
      selection['treeUri'],
      iosBookmarkId: selection['iosBookmarkId'],
      platform: selection['platform'],
    );
    ref.invalidate(songsProvider);
  }

  // ------------------------------------------------------------------ tiles

  Widget _buildQuickPickTile(
    Song song,
    AudioPlayerManager audioManager,
    List<Song> contextQueue,
  ) {
    return AppSurface(
      padding: EdgeInsets.zero,
      borderRadius: AppTokens.brSm,
      onTap: () => audioManager.playSong(
        song,
        contextQueue: contextQueue,
        playlistId: audioManager.currentPlaylistId,
      ),
      child: Row(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppTokens.rSm),
              ),
              child: AlbumArtImage(
                url: song.coverUrl ?? '',
                filename: song.filename,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                memCacheHeight: 120,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.rowTitle(context).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.meta(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s2),
        ],
      ),
    );
  }

  Widget _buildAutoPlaylistCard(
    Playlist playlist,
    AudioPlayerManager audioManager,
    WidgetRef ref,
  ) {
    final userData = ref.watch(userDataProvider);
    final songs = ref.watch(songsProvider).value ?? [];
    final isPinned =
        userData.recommendationPreferences[playlist.id]?.isPinned ?? false;

    final playlistSongs = <Song>[];
    for (final ps in playlist.songs) {
      final song =
          songs.where((s) => s.filename == ps.songFilename).firstOrNull;
      if (song != null) playlistSongs.add(song);
    }

    if (playlistSongs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.s4),
      child: AppMediaCard(
        size: _cardSize,
        title: playlist.name,
        subtitle: playlist.description,
        artwork: FolderGridImage(
          songs: playlistSongs,
          size: _cardSize,
          isGridItem: true,
        ),
        badge: isPinned
            ? Icon(
                Icons.push_pin_rounded,
                size: 14,
                color: AppTokens.accentOf(context, ref),
              )
            : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SongListScreen(
              title: playlist.name,
              songs: playlistSongs,
              playlistId: playlist.id,
            ),
          ),
        ),
        onLongPress: () => _showMixOptions(
          context,
          ref,
          playlist.id,
          playlist.name,
          playlist.description,
          playlistSongs,
          isPinned,
        ),
      ),
    );
  }

  Widget _buildAutoMoodMixCard(AutoMoodMixState moodMixState) {
    if (!moodMixState.hasEnoughData || moodMixState.selectedMood == null) {
      return const SizedBox.shrink();
    }

    final accent = AppTokens.accentOf(context, ref);

    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.s4),
      child: AppMediaCard(
        size: _cardSize,
        title: moodMixState.displayName,
        subtitle: moodMixState.description,
        artwork: Container(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.30),
            Theme.of(context).scaffoldBackgroundColor,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 38, color: accent),
              const SizedBox(height: AppTokens.s2),
              Text(
                moodMixState.selectedMood!.name,
                style: AppTokens.cardTitle(context).copyWith(fontSize: 17),
              ),
            ],
          ),
        ),
        onTap: () {
          if (moodMixState.songs.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: moodMixState.displayName,
                  songs: moodMixState.songs,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildQueueCard(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    AudioPlayerManager audioManager,
  ) {
    final songsAsync = ref.watch(songsProvider);
    final trackCount = snapshot.songFilenames.length;

    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.s3),
      child: AppMediaCard(
        size: _queueCardSize,
        title: snapshot.timestampLabel,
        subtitle:
            '${snapshot.displayDate} · $trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
        artwork: _HomeQueueArtwork(
          snapshot: snapshot,
          songsAsync: songsAsync,
          size: _queueCardSize,
        ),
        onTap: () => _showQueueApplySheet(context, ref, snapshot, audioManager),
      ),
    );
  }

  // ----------------------------------------------------------------- sheets

  void _showQueueApplySheet(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    AudioPlayerManager audioManager,
  ) {
    showAppSheet(
      context,
      title: snapshot.timestampLabel,
      builder: (sheetContext) => Consumer(
        builder: (ctx, innerRef, _) {
          final songsAsync =
              innerRef.watch(queueSnapshotSongsProvider(snapshot.id));

          return songsAsync.when(
            loading: () => const SizedBox(height: 120, child: AppLoading()),
            error: (_, __) => const SizedBox(height: 80),
            data: (songs) => Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s5,
                0,
                AppTokens.s5,
                AppTokens.s4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}',
                    style: AppTokens.meta(context),
                  ),
                  const SizedBox(height: AppTokens.s4),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      audioManager.replaceQueue(
                        songs,
                        playlistId: snapshot.source,
                        forceLinear: true,
                        clearCurrentSong: true,
                      );
                      appSnack(
                        context,
                        'Playing ${songs.length} tracks',
                        actionLabel: 'Open Player',
                        onAction: () =>
                            Navigator.push(context, PlayerPageRoute()),
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play Now'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: AppTokens.s2),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      audioManager.setPendingQueueReplacement(
                        songs,
                        playlistId: snapshot.source,
                      );
                      appSnack(
                        context,
                        '${songs.length} tracks will play after current song',
                        actionLabel: 'Cancel',
                        onAction: audioManager.cancelPendingQueueReplacement,
                      );
                    },
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Play After Current Song'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMixOptions(
    BuildContext context,
    WidgetRef ref,
    String id,
    String currentTitle,
    String? description,
    List<Song> songs,
    bool isPinned,
  ) {
    showAppSheet(
      context,
      title: currentTitle,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: Icons.playlist_add_rounded,
            label: 'Save to new playlist',
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await showAppTextPrompt(
                context,
                title: 'Playlist Name',
                initialValue: currentTitle,
              );
              if (name == null || !context.mounted) return;

              final notifier = ref.read(userDataProvider.notifier);
              await notifier.createPlaylist(name, songs.first.filename);
              if (songs.length > 1) {
                final newPlaylistId =
                    ref.read(userDataProvider).playlists.first.id;
                await notifier.bulkAddSongsToPlaylist(
                  newPlaylistId,
                  songs.skip(1).map((s) => s.filename).toList(),
                );
              }
              if (context.mounted) {
                appSnack(context, 'Created playlist "$name"',
                    tone: AppTone.success);
              }
            },
          ),
          AppSheetAction(
            icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin recommendation',
            onTap: () {
              Navigator.pop(sheetContext);
              ref.read(userDataProvider.notifier).pinRecommendation(
                    id,
                    !isPinned,
                    songs: !isPinned ? songs : null,
                    title: currentTitle,
                    description: description,
                  );
            },
          ),
          AppSheetAction(
            icon: Icons.edit_rounded,
            label: 'Rename recommendation',
            onTap: () async {
              Navigator.pop(sheetContext);
              final newName = await showAppTextPrompt(
                context,
                title: 'Rename Recommendation',
                initialValue: currentTitle,
              );
              if (newName == null) return;
              ref.read(userDataProvider.notifier).renameRecommendation(
                    id,
                    newName,
                    songs: songs,
                    description: description,
                  );
            },
          ),
          AppSheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove recommendation',
            isDanger: true,
            onTap: () async {
              Navigator.pop(sheetContext);
              final confirmed = await showAppConfirm(
                context,
                title: 'Remove recommendation?',
                message: 'Are you sure you want to remove "$currentTitle"?',
                confirmLabel: 'Remove',
                isDanger: true,
              );
              if (confirmed == true) {
                ref.read(userDataProvider.notifier).removeRecommendation(id);
              }
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final settings = ref.watch(settingsProvider);
    final songsAsyncValue = ref.watch(songsProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final accent = AppTokens.accentOf(context, ref);

    ref.listen(songsProvider, (previous, next) {
      next.whenData((songs) {
        if (songs.isNotEmpty && (previous == null || !previous.hasValue)) {
          audioManager.init(songs, autoSelect: true);
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: songsAsyncValue.when(
        loading: () => const AppLoading(),
        error: (error, stack) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: error.toString(),
          tone: AppTone.danger,
          actionLabel: 'Try Again',
          actionIcon: Icons.refresh_rounded,
          onAction: () => ref.invalidate(songsProvider),
        ),
        data: (songs) {
          if (songs.isEmpty) {
            return AppEmptyState(
              icon: Icons.music_off_rounded,
              title: 'No songs found',
              message: 'Select your music folder to start listening offline.',
              actionLabel: 'Select Music Folder',
              actionIcon: Icons.folder_open_rounded,
              onAction: _selectMusicFolder,
            );
          }

          final userData = ref.watch(userDataProvider);
          final shuffleState =
              ref.watch(audioPlayerManagerProvider).shuffleStateNotifier.value;
          final playCounts = ref.watch(playCountsProvider);

          final sortedSongs = LibraryLogic.sortSongs(
            songs,
            settings.sortOrder,
            userData: userData,
            shuffleConfig: shuffleState.config,
            playCounts: playCounts,
          );

          final topRecommendations = ref.watch(recommendationsProvider);
          final mixedPlaylists = ref.watch(mixedPlaylistsProvider);
          final queueHistory = ref.watch(queueHistoryProvider).value ?? [];
          final displayQueues = queueHistory.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(songsProvider.notifier).refresh(),
                ref.read(userDataProvider.notifier).refresh(force: true),
              ]);
              ref.invalidate(autoMoodMixProvider);
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: CustomScrollView(
                controller: widget.scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  AppSliverHeader(
                    title: 'Wispie',
                    isScrolled: _isScrolled,
                    actions: [
                      IconButton(
                        tooltip: 'Shuffle all',
                        icon: Icon(Icons.shuffle_rounded, color: accent),
                        onPressed: () => audioManager.shuffleAndPlay(
                          songs,
                          isRestricted: false,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SearchScreen()),
                        ),
                      ),
                    ],
                  ),

                  // Quick Picks
                  if (settings.showQuickPicks &&
                      topRecommendations.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: AppSectionHeader(label: 'Quick Picks'),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.s5,
                        0,
                        AppTokens.s5,
                        AppTokens.s2,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 64,
                          crossAxisSpacing: AppTokens.s3,
                          mainAxisSpacing: AppTokens.s3,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildQuickPickTile(
                            topRecommendations[index],
                            audioManager,
                            sortedSongs,
                          ),
                          childCount: topRecommendations.length.clamp(0, 6),
                        ),
                      ),
                    ),
                  ],

                  // Recent Queues
                  if (settings.showRecentQueues &&
                      displayQueues.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: AppSectionHeader(
                        label: 'Recent Queues',
                        actionLabel: 'See All',
                        onActionTap: () => Navigator.push(
                          context,
                          PlayerPageRoute(
                            initialPane: PlayerPane.queue,
                            queueShowsHistory: true,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _queueCardSize + 58,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s5,
                          ),
                          itemCount: displayQueues.length,
                          itemBuilder: (context, index) => _buildQueueCard(
                            context,
                            ref,
                            displayQueues[index],
                            audioManager,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // For You
                  if (settings.showForYou) ...[
                    const SliverToBoxAdapter(
                      child: AppSectionHeader(label: 'For You'),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _cardSize + 66,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s5,
                          ),
                          itemCount: mixedPlaylists.length + 1,
                          itemBuilder: (context, index) {
                            final autoMoodMix = ref.watch(autoMoodMixProvider);
                            if (index == 0 && autoMoodMix.hasEnoughData) {
                              return _buildAutoMoodMixCard(autoMoodMix);
                            }
                            final playlistIndex =
                                autoMoodMix.hasEnoughData ? index - 1 : index;
                            if (playlistIndex < mixedPlaylists.length) {
                              return _buildAutoPlaylistCard(
                                mixedPlaylists[playlistIndex],
                                audioManager,
                                ref,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                  ],

                  // Library
                  SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Expanded(
                          child: AppSectionHeader(label: 'Library'),
                        ),
                        const SortMenu(),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppTokens.s2,
                            right: AppTokens.s5,
                            top: AppTokens.s2,
                          ),
                          child: Text(
                            '${songs.length} tracks',
                            style: AppTokens.meta(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = sortedSongs[index];
                        return SongListItem(
                          song: song,
                          heroTagPrefix: 'all_songs',
                          onTap: () => audioManager.playSong(
                            song,
                            contextQueue: sortedSongs,
                            playlistId: audioManager.currentPlaylistId,
                          ),
                        );
                      },
                      childCount: sortedSongs.length,
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
        },
      ),
    );
  }
}

/// Four-up collage of the covers in a saved queue.
class _HomeQueueArtwork extends StatelessWidget {
  final QueueSnapshot snapshot;
  final AsyncValue<List<Song>> songsAsync;
  final double size;

  const _HomeQueueArtwork({
    required this.snapshot,
    required this.songsAsync,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final songs = songsAsync.maybeWhen(
      data: (allSongs) {
        final songMap = {for (final song in allSongs) song.filename: song};
        return snapshot.songFilenames
            .map((filename) => songMap[filename])
            .whereType<Song>()
            .take(4)
            .toList();
      },
      orElse: () => const <Song>[],
    );

    final tileSize = (size - 3) / 2;
    final fallback = AppTokens.surface(2);

    return Container(
      width: size,
      height: size,
      color: AppTokens.surface(1),
      child: songs.isEmpty
          ? Center(
              child: Icon(
                Icons.queue_music_rounded,
                size: 40,
                color: AppTokens.fgTertiary,
              ),
            )
          : Wrap(
              spacing: 1,
              runSpacing: 1,
              children: List.generate(4, (index) {
                final song = index < songs.length ? songs[index] : null;
                return SizedBox(
                  width: tileSize,
                  height: tileSize,
                  child: song == null
                      ? ColoredBox(color: fallback)
                      : AlbumArtImage(
                          url: song.coverUrl ?? '',
                          width: tileSize,
                          height: tileSize,
                          fit: BoxFit.cover,
                          errorWidget: ColoredBox(
                            color: fallback,
                            child: Icon(
                              Icons.music_note_rounded,
                              color: AppTokens.fgTertiary,
                              size: 18,
                            ),
                          ),
                        ),
                );
              }),
            ),
    );
  }
}

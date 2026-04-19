import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/album_art_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/telemetry_service.dart';
import '../../services/library_logic.dart';
import '../../models/song.dart';
import '../../models/queue_snapshot.dart';
import '../../services/audio_player_manager.dart';
import '../../providers/queue_history_provider.dart';
import '../../providers/mixed_playlists_provider.dart';
import '../../providers/auto_mood_mix_provider.dart';
import '../../models/playlist.dart';
import 'song_list_screen.dart';
import 'queue_history_screen.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/sort_menu.dart';
import 'search_screen.dart';
import 'player_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _bottomDockDragDistance = 88.0;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to access selected folder")),
        );
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

  Widget _buildQuickPickTile(Song song, ThemeData theme,
      AudioPlayerManager audioManager, List<Song> contextSongs) {
    return GestureDetector(
      onTap: () {
        audioManager.playSong(
          song,
          contextQueue: contextSongs,
          playlistId: 'quick_picks',
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
                child: AlbumArtImage(
                  url: song.coverUrl ?? '',
                  filename: song.filename,
                  fit: BoxFit.cover,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoPlaylistCard(Playlist playlist, ThemeData theme,
      AudioPlayerManager audioManager, WidgetRef ref) {
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
      padding: const EdgeInsets.only(right: 20),
      child: GestureDetector(
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
        onLongPress: () {
          _showMixOptions(context, ref, playlist.id, playlist.name,
              playlist.description, playlistSongs, isPinned);
        },
        child: SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: FolderGridImage(
                        songs: playlistSongs,
                        size: 200,
                        isGridItem: true,
                      ),
                    ),
                  ),
                  if (isPinned)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.push_pin_rounded,
                            size: 16, color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                playlist.description ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoMoodMixCard(
    ThemeData theme,
    AutoMoodMixState moodMixState,
  ) {
    if (!moodMixState.hasEnoughData || moodMixState.selectedMood == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: GestureDetector(
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
        child: SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.85),
                      theme.colorScheme.secondary.withValues(alpha: 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 42, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      moodMixState.selectedMood!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                moodMixState.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                moodMixState.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    AudioPlayerManager audioManager,
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final songsAsync = ref.watch(songsProvider);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          _showQueueApplySheet(
              context, ref, snapshot, audioManager, colorScheme);
        },
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeQueueArtwork(
                snapshot: snapshot,
                songsAsync: songsAsync,
                size: 120,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.timestampLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                '${snapshot.displayDate} · ${snapshot.songFilenames.length} ${snapshot.songFilenames.length == 1 ? 'track' : 'tracks'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueApplySheet(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    AudioPlayerManager audioManager,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (ctx, innerRef, _) {
          final songsAsync =
              innerRef.watch(queueSnapshotSongsProvider(snapshot.id));
          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(20),
            child: songsAsync.when(
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SizedBox(height: 80),
              data: (songs) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.timestampLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        audioManager.replaceQueue(songs,
                            playlistId: snapshot.source, forceLinear: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Playing ${songs.length} tracks'),
                            action: SnackBarAction(
                              label: 'Open Player',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const PlayerScreen()),
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play Now'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        audioManager.setPendingQueueReplacement(songs,
                            playlistId: snapshot.source);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '${songs.length} tracks will play after current song'),
                            action: SnackBarAction(
                              label: 'Cancel',
                              onPressed:
                                  audioManager.cancelPendingQueueReplacement,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Play After Current Song'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
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
      bool isPinned) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Save to new playlist?'),
              onTap: () async {
                Navigator.pop(context);
                final name = await _showSimpleNameDialog(context,
                    title: 'Playlist Name', initialValue: currentTitle);
                if (name != null && name.isNotEmpty && context.mounted) {
                  final notifier = ref.read(userDataProvider.notifier);
                  await notifier.createPlaylist(name, songs.first.filename);
                  if (songs.length > 1) {
                    final newPlaylistId =
                        ref.read(userDataProvider).playlists.first.id;
                    await notifier.bulkAddSongsToPlaylist(newPlaylistId,
                        songs.skip(1).map((s) => s.filename).toList());
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Created playlist "$name"')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(
                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              title: Text(isPinned ? 'Unpin' : 'Pin recommendation'),
              onTap: () {
                Navigator.pop(context);
                ref.read(userDataProvider.notifier).pinRecommendation(
                      id,
                      !isPinned,
                      songs: !isPinned ? songs : null,
                      title: currentTitle,
                      description: description,
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename recommendation'),
              onTap: () async {
                Navigator.pop(context);
                final newName = await _showSimpleNameDialog(context,
                    title: 'Rename Recommendation', initialValue: currentTitle);
                if (newName != null && newName.isNotEmpty) {
                  ref.read(userDataProvider.notifier).renameRecommendation(
                        id,
                        newName,
                        songs: songs,
                        description: description,
                      );
                }
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Remove recommendation',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showRemoveConfirmation(context, ref, id, currentTitle);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showSimpleNameDialog(BuildContext context,
      {required String title, String? initialValue}) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter name...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRemoveConfirmation(
      BuildContext context, WidgetRef ref, String id, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Recommendation?'),
        content: Text('Are you sure you want to remove "$title"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(userDataProvider.notifier).removeRecommendation(id);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final theme = Theme.of(context);
    final songsAsyncValue = ref.watch(songsProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

    // Listen for data changes to initialize audio
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
        data: (songs) {
          final sortOrder = ref.watch(settingsProvider).sortOrder;
          final userData = ref.watch(userDataProvider);
          final shuffleState =
              ref.watch(audioPlayerManagerProvider).shuffleStateNotifier.value;
          final playCounts = ref.watch(playCountsProvider).value ?? {};

          final sortedSongs = LibraryLogic.sortSongs(
            songs,
            sortOrder,
            userData: userData,
            shuffleConfig: shuffleState.config,
            playCounts: playCounts,
          );

          if (songs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_off_outlined,
                        size: 80, color: theme.colorScheme.secondary),
                    const SizedBox(height: 16),
                    Text('No songs found',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Select your music folder to start listening offline.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _selectMusicFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select Music Folder'),
                    ),
                  ],
                ),
              ),
            );
          }

          final topRecommendations = ref.watch(recommendationsProvider);
          final mixedPlaylists = ref.watch(mixedPlaylistsProvider);
          final queueHistory = ref.watch(queueHistoryProvider).value ?? [];

          final displayQueues = queueHistory.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await TelemetryService.instance.trackEvent(
                  'library_action',
                  {
                    'action': 'pull_to_refresh',
                    'screen': 'home',
                  },
                  requiredLevel: 2);

              await Future.wait([
                ref.read(songsProvider.notifier).refresh(),
                ref.read(userDataProvider.notifier).refresh(force: true),
              ]);
              // Invalidate auto mood mix to force regeneration on next watch
              ref.invalidate(autoMoodMixProvider);
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          20, MediaQuery.of(context).padding.top + 16, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Wispie',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle_rounded,
                                    color: theme.colorScheme.primary),
                                onPressed: () {
                                  if (songs.isNotEmpty) {
                                    audioManager.shuffleAndPlay(songs,
                                        isRestricted: false);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.search_rounded),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const SearchScreen()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (topRecommendations.isNotEmpty) ...[
                            Text(
                              'Quick Picks',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 64,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: topRecommendations.length.clamp(0, 6),
                              itemBuilder: (context, index) {
                                final song = topRecommendations[index];
                                final contextSongs =
                                    topRecommendations.take(6).toList();
                                return _buildQuickPickTile(
                                    song, theme, audioManager, contextSongs);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (displayQueues.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent Queues',
                              style: theme.textTheme.titleLarge,
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const QueueHistoryScreen()),
                              ),
                              child: const Text('See All'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: displayQueues.length,
                          itemBuilder: (context, index) {
                            final snapshot = displayQueues[index];
                            return _buildQueueCard(
                                context, ref, snapshot, audioManager, theme);
                          },
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Text(
                            'For You',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        SizedBox(
                          height: 300,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: mixedPlaylists.length + 1,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemBuilder: (context, index) {
                              final autoMoodMix =
                                  ref.watch(autoMoodMixProvider);
                              if (index == 0 && autoMoodMix.hasEnoughData) {
                                return _buildAutoMoodMixCard(
                                    theme, autoMoodMix);
                              }
                              final playlistIndex =
                                  autoMoodMix.hasEnoughData ? index - 1 : index;
                              if (playlistIndex < mixedPlaylists.length) {
                                final playlist = mixedPlaylists[playlistIndex];
                                return _buildAutoPlaylistCard(
                                    playlist, theme, audioManager, ref);
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Library',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(width: 8),
                              const SortMenu(),
                            ],
                          ),
                          Text(
                            '${songs.length} tracks',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = sortedSongs[index];
                        return SongListItem(
                          song: song,
                          heroTagPrefix: 'all_songs',
                          onTap: () {
                            audioManager.playSong(song,
                                contextQueue: sortedSongs);
                          },
                        );
                      },
                      childCount: sortedSongs.length,
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(songsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeQueueArtwork extends StatelessWidget {
  final QueueSnapshot snapshot;
  final AsyncValue<List<Song>> songsAsync;
  final double size;
  final ColorScheme colorScheme;

  const _HomeQueueArtwork({
    required this.snapshot,
    required this.songsAsync,
    required this.size,
    required this.colorScheme,
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

    return _HomeQueueCoverCollage(
      songs: songs,
      size: size,
      borderRadius: 20,
      backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.6),
      fallbackColor: colorScheme.onSecondaryContainer.withValues(alpha: 0.14),
      iconColor: colorScheme.onSecondaryContainer,
    );
  }
}

class _HomeQueueCoverCollage extends StatelessWidget {
  final List<Song> songs;
  final double size;
  final double borderRadius;
  final Color backgroundColor;
  final Color fallbackColor;
  final Color iconColor;

  const _HomeQueueCoverCollage({
    required this.songs,
    required this.size,
    required this.borderRadius,
    required this.backgroundColor,
    required this.fallbackColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = songs.take(4).toList();
    final tileSize = (size - 3) / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        child: tiles.isEmpty
            ? Center(
                child:
                    Icon(Icons.queue_music_rounded, size: 48, color: iconColor),
              )
            : Wrap(
                spacing: 1,
                runSpacing: 1,
                children: List.generate(4, (index) {
                  final song = index < tiles.length ? tiles[index] : null;
                  return SizedBox(
                    width: tileSize,
                    height: tileSize,
                    child: song == null
                        ? ColoredBox(color: fallbackColor)
                        : AlbumArtImage(
                            url: song.coverUrl ?? '',
                            width: tileSize,
                            height: tileSize,
                            fit: BoxFit.cover,
                            errorWidget: ColoredBox(
                              color: fallbackColor,
                              child: Icon(
                                Icons.music_note_rounded,
                                color: iconColor.withValues(alpha: 0.6),
                                size: 18,
                              ),
                            ),
                          ),
                  );
                }),
              ),
      ),
    );
  }
}

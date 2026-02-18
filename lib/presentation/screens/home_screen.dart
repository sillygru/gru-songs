import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/album_art_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/android_storage_service.dart';
import '../../services/telemetry_service.dart';
import '../../services/library_logic.dart';
import '../../models/song.dart';
import '../../services/audio_player_manager.dart';
import '../../providers/session_history_provider.dart';
import '../../providers/mixed_playlists_provider.dart';
import '../../providers/auto_mood_mix_provider.dart';
import '../../models/playlist.dart';
import '../../models/mood_tag.dart';
import 'song_list_screen.dart';
import 'session_detail_screen.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/sort_menu.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _selectMusicFolder() async {
    if (Platform.isAndroid) {
      final selection = await AndroidStorageService.pickTree();
      if (selection == null) return;
      if (selection.path == null || selection.path!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unable to access selected folder")),
          );
        }
        return;
      }
      final storage = ref.read(storageServiceProvider);
      await storage.addMusicFolder(selection.path!, selection.treeUri);
      ref.invalidate(songsProvider);
      return;
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;
    final storage = ref.read(storageServiceProvider);
    await storage.addMusicFolder(selectedDirectory, null);
    ref.invalidate(songsProvider);
  }

  Widget _buildQuickPickTile(
      Song song, ThemeData theme, AudioPlayerManager audioManager) {
    return GestureDetector(
      onTap: () {
        audioManager.playSong(song, playlistId: 'quick_picks');
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

  Future<void> _showMoodMixGenerator(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
  ) async {
    if (songs.isEmpty) return;
    final userData = ref.read(userDataProvider);
    if (userData.moodTags.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create moods first from song options')),
        );
      }
      return;
    }

    final selectedMoodIds = <String>{};
    double length = 25;
    double diversity = 0.65;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mood Mix',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: userData.moodTags.map((mood) {
                      final selected = selectedMoodIds.contains(mood.id);
                      return FilterChip(
                        label: Text(mood.name),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() {
                            if (selected) {
                              selectedMoodIds.remove(mood.id);
                            } else {
                              selectedMoodIds.add(mood.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('Tracks: ${length.round()}'),
                  Slider(
                    value: length,
                    min: 10,
                    max: 60,
                    divisions: 10,
                    label: length.round().toString(),
                    onChanged: (value) => setModalState(() => length = value),
                  ),
                  Text('Diversity: ${(diversity * 100).round()}%'),
                  Slider(
                    value: diversity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: '${(diversity * 100).round()}%',
                    onChanged: (value) =>
                        setModalState(() => diversity = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedMoodIds.isEmpty
                          ? null
                          : () async {
                              final generated = await ref
                                  .read(userDataProvider.notifier)
                                  .generateMoodMix(
                                    moodIds: selectedMoodIds.toList(),
                                    length: length.round(),
                                    diversity: diversity,
                                  );
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (generated.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('No songs match those moods')),
                                  );
                                }
                                return;
                              }
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SongListScreen(
                                      title: 'Mood Mix',
                                      songs: generated,
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Generate'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMixOptions(BuildContext context, WidgetRef ref, String id,
      String currentTitle, String? description, List<Song> songs, bool isPinned,
      {bool isSession = false}) {
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
          final sessionHistory = ref.watch(sessionHistoryProvider).value ?? [];

          final recentSessions = sessionHistory.where((s) {
            if (s.songCount <= 0) return false;
            if (userData.removedRecommendations.contains(s.id)) return false;
            return true;
          }).toList();

          // Sort recent sessions: Pinned ones first
          recentSessions.sort((a, b) {
            final aPinned =
                userData.recommendationPreferences[a.id]?.isPinned ?? false;
            final bPinned =
                userData.recommendationPreferences[b.id]?.isPinned ?? false;
            if (aPinned && !bPinned) return -1;
            if (!aPinned && bPinned) return 1;
            return 0;
          });

          final displaySessions = recentSessions.take(10).toList();

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
                              return _buildQuickPickTile(
                                  song, theme, audioManager);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (displaySessions.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(
                        'Repeat previous queue?',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: displaySessions.length,
                        itemBuilder: (context, index) {
                          final session = displaySessions[index];
                          final sessionSongs = (session.events ?? [])
                              .map((e) => e.song)
                              .whereType<Song>()
                              .toList();

                          if (sessionSongs.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final pref =
                              userData.recommendationPreferences[session.id];
                          final isPinned = pref?.isPinned ?? false;
                          final displayTitle =
                              pref?.customTitle ?? session.displayDate;

                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SessionDetailScreen(session: session),
                                  ),
                                );
                              },
                              onLongPress: () {
                                _showMixOptions(context, ref, session.id,
                                    displayTitle, null, sessionSongs, isPinned,
                                    isSession: true);
                              },
                              child: SizedBox(
                                width: 120,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: FolderGridImage(
                                            songs: sessionSongs,
                                            size: 120,
                                          ),
                                        ),
                                        if (isPinned)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                  Icons.push_pin_rounded,
                                                  size: 12,
                                                  color: theme
                                                      .colorScheme.primary),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      '${sessionSongs.length} tracks',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: Colors.white54,
                                              fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
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
                            final autoMoodMix = ref.watch(autoMoodMixProvider);
                            if (index == 0 && autoMoodMix.hasEnoughData) {
                              return _buildAutoMoodMixCard(theme, autoMoodMix);
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

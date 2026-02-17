import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../widgets/song_list_item.dart';
import '../widgets/sort_menu.dart';
import '../widgets/duration_display.dart';
import '../widgets/bulk_selection_bar.dart';
import '../widgets/folder_grid_image.dart';
import '../../providers/selection_provider.dart';
import 'select_songs_screen.dart';

class SongListScreen extends ConsumerWidget {
  final String title;
  final List<Song> songs;
  final String? playlistId;

  const SongListScreen({
    super.key,
    required this.title,
    required this.songs,
    this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final selectionState = ref.watch(selectionProvider);
    final sortOrder = ref.watch(settingsProvider).sortOrder;
    final userData = ref.watch(userDataProvider);
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider).value ?? {};
    final colorScheme = Theme.of(context).colorScheme;

    final sortedSongs = LibraryLogic.sortSongs(
      songs,
      sortOrder,
      userData: userData,
      shuffleConfig: shuffleConfig,
      playCounts: playCounts,
    );

    final isPlaylist = playlistId != null;

    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selectionState.isSelectionMode) {
          ref.read(selectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              actions: [
                const SortMenu(),
                if (playlistId != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showPlaylistOptions(context, ref),
                    tooltip: 'Playlist Options',
                  ),
                if (playlistId == null && sortedSongs.length >= 2)
                  IconButton(
                    icon: const Icon(Icons.merge_type),
                    onPressed: () async {
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SelectSongsScreen(
                            songs: sortedSongs,
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Merged ${selected.length} songs')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
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
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FolderGridImage(
                            songs: sortedSongs,
                            size: 220,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onLongPress: isPlaylist
                          ? () => _showRenameDialog(context, ref)
                          : null,
                      child: Text(
                        title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (sortedSongs.isNotEmpty)
                      CollectionDurationDisplay(
                        songs: sortedSongs,
                        showSongCount: true,
                        compact: true,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: sortedSongs.isNotEmpty
                              ? () {
                                  audioManager.shuffleAndPlay(sortedSongs,
                                      isRestricted: true);
                                }
                              : null,
                          icon: const Icon(Icons.shuffle),
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
                                  audioManager.playSong(
                                    sortedSongs.first,
                                    contextQueue: sortedSongs,
                                    playlistId: playlistId,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow),
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            if (sortedSongs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note_outlined,
                          size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text('No songs in this list',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = sortedSongs[index];

                    return SongListItem(
                      song: song,
                      heroTagPrefix: 'song_list_$title',
                      playlistId: playlistId,
                      onTap: () {
                        audioManager.playSong(song,
                            contextQueue: sortedSongs, playlistId: playlistId);
                      },
                    );
                  },
                  childCount: sortedSongs.length,
                ),
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

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    if (playlistId == null) return;

    final controller = TextEditingController(text: title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text;
              if (newName.isNotEmpty && newName != title) {
                ref
                    .read(userDataProvider.notifier)
                    .updatePlaylistName(playlistId!, newName);
              }
              Navigator.pop(context);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    if (playlistId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(userDataProvider.notifier).deletePlaylist(playlistId!);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

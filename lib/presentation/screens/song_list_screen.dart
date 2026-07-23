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
import '../tokens/app_tokens.dart';
import '../components/app_dialog.dart';
import '../components/app_screen_header.dart';
import '../components/app_sheet.dart';
import '../components/app_feedback.dart';
import '../routes/app_page_route.dart';

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
    final playCounts = ref.watch(playCountsProvider);

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
            AppSliverHeader(
              title: title,
              large: false,
              floating: true,
              snap: true,
              actions: [
                const SortMenu(),
                if (playlistId != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showPlaylistOptions(context, ref),
                    tooltip: 'Playlist Options',
                  ),
                if (playlistId == null && sortedSongs.length >= 2)
                  IconButton(
                    icon: const Icon(Icons.merge_type_rounded),
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
                                .createMergedGroup(selected,
                                    priorityFilename: priority);
                            if (context.mounted) {
                              appSnack(
                                  context, 'Merged ${selected.length} songs');
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
                    Center(
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: ClipRRect(
                          borderRadius: AppTokens.brMd,
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
                                  audioManager.replaceQueue(
                                    sortedSongs,
                                    playlistId: playlistId,
                                    forceLinear: true,
                                    clearCurrentSong: true,
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
              const SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: Icons.music_note_rounded,
                  title: 'No songs in this list',
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

    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: Icons.edit_rounded,
            label: 'Rename',
            onTap: () {
              Navigator.pop(sheetContext);
              _showRenameDialog(context, ref);
            },
          ),
          AppSheetAction(
            icon: Icons.delete_outline_rounded,
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
      ref.read(userDataProvider.notifier).updatePlaylistName(
            playlistId!,
            newName,
          );
    }
  }

  Future<void> _showDeleteConfirmation(
      BuildContext context, WidgetRef ref) async {
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
}

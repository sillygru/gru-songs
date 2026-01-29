import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../widgets/song_list_item.dart';
import '../widgets/sort_menu.dart';
import '../widgets/duration_display.dart';
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
    final sortOrder = ref.watch(settingsProvider).sortOrder;
    final userData = ref.watch(userDataProvider);
    final shuffleConfig = audioManager.shuffleStateNotifier.value.config;
    final playCounts = ref.watch(playCountsProvider).value ?? {};

    final sortedSongs = LibraryLogic.sortSongs(
      songs,
      sortOrder,
      userData: userData,
      shuffleConfig: shuffleConfig,
      playCounts: playCounts,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              const SortMenu(),
              // Merge button - only show for non-playlist views
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
                                  content:
                                      Text('Merged ${selected.length} songs')),
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
              IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: () {
                  if (sortedSongs.isNotEmpty) {
                    audioManager.shuffleAndPlay(sortedSongs,
                        isRestricted: true);
                  }
                },
                tooltip: 'Shuffle',
              ),
            ],
          ),
          // Total duration header
          if (sortedSongs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    CollectionDurationDisplay(
                      songs: sortedSongs,
                      showSongCount: true,
                      compact: false,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
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
                      audioManager.playSong(song, contextQueue: sortedSongs);
                    },
                  );
                },
                childCount: sortedSongs.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../widgets/song_list_item.dart';
import '../widgets/sort_menu.dart';

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

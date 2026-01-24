import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/song_list_item.dart';

class SongListScreen extends ConsumerWidget {
  final String title;
  final List<Song> songs;

  const SongListScreen({
    super.key,
    required this.title,
    required this.songs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: () {
                  if (songs.isNotEmpty) {
                    audioManager.shuffleAndPlay(songs, isRestricted: true);
                  }
                },
                tooltip: 'Shuffle',
              ),
            ],
          ),
          if (songs.isEmpty)
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
            SliverFixedExtentList(
              itemExtent: 80,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = songs[index];
                  return SongListItem(
                    song: song,
                    heroTagPrefix: 'song_list_$title',
                    onTap: () {
                      audioManager.playSong(song, contextQueue: songs);
                    },
                  );
                },
                childCount: songs.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

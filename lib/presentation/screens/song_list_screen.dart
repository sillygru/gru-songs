import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gru_image.dart';
import '../widgets/song_options_menu.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';

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
    final userData = ref.watch(userDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: () {
              if (songs.isNotEmpty) {
                audioManager.shuffleAndPlay(songs);
              }
            },
            tooltip: 'Shuffle',
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
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
            )
          : ListView.builder(
              itemCount: songs.length,
              padding: const EdgeInsets.only(bottom: 100),
              itemBuilder: (context, index) {
                final song = songs[index];
                final isSuggestLess =
                    userData.isSuggestLess(song.filename);

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GruImage(
                      url: song.coverUrl ?? '',
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: const Icon(Icons.music_note),
                    ),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSuggestLess ? Colors.grey : null,
                      decoration:
                          isSuggestLess ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isSuggestLess ? Colors.grey : null),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      showSongOptionsMenu(
                          context, ref, song.filename, song.title,
                          song: song);
                    },
                  ),
                  onTap: () {
                    audioManager.playSong(song, contextQueue: songs);
                  },
                );
              },
            ),
    );
  }
}

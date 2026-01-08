import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../providers/providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);
    final audioManager = ref.read(audioPlayerManagerProvider);
    
    // We need to match filenames to actual Song objects
    
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: songsAsync.when(
        data: (allSongs) {
            final playlistSongs = allSongs.where((s) => playlist.songFilenames.contains(s.filename)).toList();
            
            if (playlistSongs.isEmpty) {
                return const Center(child: Text("Empty Playlist"));
            }
            
            return ListView.builder(
                itemCount: playlistSongs.length,
                itemBuilder: (context, index) {
                    final song = playlistSongs[index];
                    return ListTile(
                        title: Text(song.title),
                        subtitle: Text(song.artist),
                        trailing: IconButton(
                             icon: const Icon(Icons.remove_circle_outline),
                             onPressed: () {
                                 ref.read(userDataProvider.notifier).removeSongFromPlaylist(playlist.id, song.filename);
                             },
                        ),
                        onTap: () {
                           // Play this playlist
                           // Note: This logic starts playing ONLY this playlist
                           audioManager.init(playlistSongs);
                           audioManager.player.seek(Duration.zero, index: index);
                           audioManager.player.play();
                        },
                    );
                },
            );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }
}

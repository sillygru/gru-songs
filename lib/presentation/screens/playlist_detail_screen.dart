import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);
    final audioManager = ref.read(audioPlayerManagerProvider);
    final userData = ref.watch(userDataProvider);
    
    final playlist = userData.playlists.firstWhere((p) => p.id == playlistId, orElse: () => const Playlist(id: '', name: 'Not Found', songs: []));
    
    if (playlist.id.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text("Not Found")),
          body: const Center(child: Text("Playlist not found")),
        );
    }
    
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: songsAsync.when(
        data: (allSongs) {
            final playlistSongs = <Song>[];
            final validPlaylistSongs = <PlaylistSong>[];
            
            for (final ps in playlist.songs) {
              final songIndex = allSongs.indexWhere((s) => s.filename == ps.filename);
              if (songIndex != -1) {
                playlistSongs.add(allSongs[songIndex]);
                validPlaylistSongs.add(ps);
              }
            }
            
            if (playlistSongs.isEmpty) {
                return const Center(child: Text("Empty Playlist"));
            }
            
            return ListView.builder(
                itemCount: playlistSongs.length,
                itemBuilder: (context, index) {
                    final song = playlistSongs[index];
                    final playlistSong = validPlaylistSongs[index];
                    final addedDate = "${playlistSong.addedAt.day}/${playlistSong.addedAt.month}/${playlistSong.addedAt.year}";

                    return ListTile(
                        title: Text(song.title),
                        subtitle: Text("${song.artist} • Added $addedDate"),
                        trailing: IconButton(
                             icon: const Icon(Icons.remove_circle_outline),
                             onPressed: () {
                                 ref.read(userDataProvider.notifier).removeSongFromPlaylist(playlist.id, song.filename);
                             },
                        ),
                        onTap: () {
                           // Play this playlist
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

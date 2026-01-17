import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gru_image.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/now_playing_bar.dart';
import '../widgets/song_options_menu.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);
    final audioManager = ref.read(audioPlayerManagerProvider);
    final userData = ref.watch(userDataProvider);
    final apiService = ref.watch(apiServiceProvider);
    
    Playlist playlist;
    if (playlistId == '__favorites__') {
      playlist = Playlist(
        id: '__favorites__',
        name: 'Favorites',
        songs: userData.favorites.map((f) => PlaylistSong(filename: f, addedAt: DateTime.now())).toList(),
      );
    } else {
      playlist = userData.playlists.firstWhere((p) => p.id == playlistId, orElse: () => const Playlist(id: '', name: 'Not Found', songs: []));
    }
    
    if (playlist.id.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text("Not Found")),
          body: const Center(child: Text("Playlist not found")),
        );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          songsAsync.when(
            data: (allSongs) {
              final playlistSongs = <Song>[];
              for (final ps in playlist.songs) {
                final songIndex = allSongs.indexWhere((s) => s.filename == ps.filename);
                if (songIndex != -1) {
                  playlistSongs.add(allSongs[songIndex]);
                }
              }
              if (playlistSongs.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: () {
                  audioManager.shuffleAndPlay(playlistSongs);
                },
                tooltip: 'Shuffle Playlist',
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(songsProvider.notifier).refresh(),
            ref.read(userDataProvider.notifier).refresh(),
          ]);
        },
        child: Stack(
          children: [
            songsAsync.when(
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
                    padding: const EdgeInsets.only(bottom: 100),
                    itemBuilder: (context, index) {
                        final song = playlistSongs[index];
                        final playlistSong = validPlaylistSongs[index];
                        final addedDate = "${playlistSong.addedAt.day}/${playlistSong.addedAt.month}/${playlistSong.addedAt.year}";
                        final isFavorite = userData.favorites.contains(song.filename);
                        final isSuggestLess = userData.suggestLess.contains(song.filename);

                        return ListTile(
                            leading: Opacity(
                              opacity: isSuggestLess ? 0.5 : 1.0,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: GruImage(
                                  url: song.coverUrl != null 
                                    ? apiService.getFullUrl(song.coverUrl!) 
                                    : apiService.getFullUrl('/stream/cover.jpg'),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorWidget: const Icon(Icons.music_note),
                                ),
                              ),
                            ),
                            title: Text(
                              song.title,
                              style: TextStyle(
                                color: isSuggestLess ? Colors.grey : null,
                                decoration: isSuggestLess ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              playlistId == '__favorites__' 
                                ? song.artist 
                                : "${song.artist} • Added $addedDate",
                              style: TextStyle(color: isSuggestLess ? Colors.grey : null),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "${song.playCount}",
                                    style: const TextStyle(
                                      fontSize: 10, 
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isSuggestLess 
                                      ? Icons.heart_broken 
                                      : (isFavorite ? Icons.favorite : Icons.favorite_border)
                                  ),
                                  color: isSuggestLess ? Colors.grey : (isFavorite ? Colors.red : null),
                                  onPressed: () {
                                    ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                                  },
                                ),
                              ],
                            ),
                            onLongPress: () {
                               showSongOptionsMenu(context, ref, song.filename, song.title, song: song);
                            },
                            onTap: () {
                               audioManager.playSong(song, contextQueue: playlistSongs);
                            },
                        );
                    },
                );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text("Error: $e")),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NowPlayingBar(),
          ),
        ],
      ),
    ),
    );
  }
}

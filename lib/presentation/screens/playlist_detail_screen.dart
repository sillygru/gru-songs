import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../widgets/now_playing_bar.dart';

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
      body: Stack(
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
                                child: CachedNetworkImage(
                                  imageUrl: song.coverUrl != null 
                                    ? apiService.getFullUrl(song.coverUrl!) 
                                    : apiService.getFullUrl('/stream/cover.jpg'),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => const Icon(Icons.music_note),
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
                               _showSongOptionsMenu(context, ref, song, userData);
                            },
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
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NowPlayingBar(),
          ),
        ],
      ),
    );
  }

  void _showSongOptionsMenu(BuildContext context, WidgetRef ref, Song song, UserDataState userData) {
    final isFavorite = userData.favorites.contains(song.filename);
    final isSuggestLess = userData.suggestLess.contains(song.filename);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                title: Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text("Add to new playlist"),
                onTap: () async {
                  Navigator.pop(context);
                  final nameController = TextEditingController();
                  final newName = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("New Playlist"),
                      content: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(hintText: "Playlist Name"),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                        TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text("Create")),
                      ],
                    ),
                  );
                  if (newName != null && newName.isNotEmpty) {
                    final newPlaylist = await ref.read(userDataProvider.notifier).createPlaylist(newName);
                    if (newPlaylist != null) {
                      await ref.read(userDataProvider.notifier).addSongToPlaylist(newPlaylist.id, song.filename);
                    }
                  }
                },
              ),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == song.filename);
                if (isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text("Add to ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).addSongToPlaylist(p.id, song.filename);
                    Navigator.pop(context);
                  },
                );
              }),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == song.filename);
                if (!isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text("Remove from ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).removeSongFromPlaylist(p.id, song.filename);
                    Navigator.pop(context);
                  },
                );
              }),
              ListTile(
                leading: Icon(isSuggestLess ? Icons.thumb_up : Icons.thumb_down_outlined, color: isSuggestLess ? Colors.orange : null),
                title: Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleSuggestLess(song.filename);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

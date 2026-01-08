import 'package:cached_network_image/cached_network_image.dart';
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
    final apiService = ref.watch(apiServiceProvider);
    
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
                    final isFavorite = userData.favorites.contains(song.filename);
                    final isSuggestLess = userData.suggestLess.contains(song.filename);

                    return ListTile(
                        leading: ClipRRect(
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
                        title: Text(song.title),
                        subtitle: Text("${song.artist} • Added $addedDate"),
                        trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                                if (value == 'favorite') {
                                    ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                                } else if (value == 'suggest_less') {
                                    ref.read(userDataProvider.notifier).toggleSuggestLess(song.filename);
                                } else if (value.startsWith('add_to_')) {
                                    final pid = value.replaceFirst('add_to_', '');
                                    await ref.read(userDataProvider.notifier).addSongToPlaylist(pid, song.filename);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to playlist")));
                                    }
                                } else if (value.startsWith('remove_from_')) {
                                    final pid = value.replaceFirst('remove_from_', '');
                                    await ref.read(userDataProvider.notifier).removeSongFromPlaylist(pid, song.filename);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Removed from playlist")));
                                    }
                                }
                            },
                            itemBuilder: (context) {
                              final List<PopupMenuEntry<String>> items = [];
                              
                              // 1. Favorite
                              items.add(PopupMenuItem(
                                value: 'favorite',
                                child: Row(
                                  children: [
                                    Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                                    const SizedBox(width: 8),
                                    Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                                  ],
                                ),
                              ));

                              // 2. Add to [playlist]
                              for (final p in userData.playlists) {
                                if (!p.songs.any((s) => s.filename == song.filename)) {
                                  items.add(PopupMenuItem(
                                    value: 'add_to_${p.id}',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.playlist_add),
                                        const SizedBox(width: 8),
                                        Text("Add to ${p.name}"),
                                      ],
                                    ),
                                  ));
                                }
                              }

                              // 3. Remove from [playlist]
                              for (final p in userData.playlists) {
                                if (p.songs.any((s) => s.filename == song.filename)) {
                                  items.add(PopupMenuItem(
                                    value: 'remove_from_${p.id}',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.remove_circle_outline),
                                        const SizedBox(width: 8),
                                        Text("Remove from ${p.name}"),
                                      ],
                                    ),
                                  ));
                                }
                              }

                              // 4. Suggest less
                              items.add(PopupMenuItem(
                                value: 'suggest_less',
                                child: Row(
                                  children: [
                                    Icon(isSuggestLess ? Icons.thumb_down : Icons.thumb_down_outlined, color: isSuggestLess ? Colors.orange : null),
                                    const SizedBox(width: 8),
                                    Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                                  ],
                                ),
                              ));

                              return items;
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

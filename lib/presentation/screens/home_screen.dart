import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/providers.dart';
import '../widgets/now_playing_bar.dart';
import 'settings_screen.dart';
import 'playlists_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
    final apiService = ref.watch(apiServiceProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final userData = ref.watch(userDataProvider);

    // Listen for data changes to initialize audio
    ref.listen(songsProvider, (previous, next) {
      next.whenData((songs) {
        if (songs.isNotEmpty) {
          audioManager.init(songs);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gru Songs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
               Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaylistsScreen()));
            },
          ),
          IconButton(
             icon: const Icon(Icons.settings),
             onPressed: () {
               Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
             },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(songsProvider);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          songsAsyncValue.when(
            data: (songs) {
              if (songs.isEmpty) {
                return const Center(child: Text('No songs found'));
              }
              return ListView.builder(
                itemCount: songs.length,
                padding: const EdgeInsets.only(bottom: 80),
                itemBuilder: (context, index) {
                  final song = songs[index];
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
                    subtitle: Text(song.artist),
                    trailing: Consumer(
                      builder: (context, ref, child) {
                         final userData = ref.watch(userDataProvider);
                         final isFavorite = userData.favorites.contains(song.filename);
                         return PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                                if (value == 'favorite') {
                                    ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                                } else if (value == 'new_playlist') {
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
                                            if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text("Created and added to $newName"))
                                                );
                                            }
                                        }
                                    }
                                } else if (value.startsWith('toggle_')) {
                                    final playlistId = value.replaceFirst('toggle_', '');
                                    final playlist = userData.playlists.firstWhere((p) => p.id == playlistId);
                                    final exists = playlist.songs.any((s) => s.filename == song.filename);
                                    
                                    if (exists) {
                                        await ref.read(userDataProvider.notifier).removeSongFromPlaylist(playlistId, song.filename);
                                        if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text("Removed from ${playlist.name}"))
                                            );
                                        }
                                    } else {
                                        await ref.read(userDataProvider.notifier).addSongToPlaylist(playlistId, song.filename);
                                        if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text("Added to ${playlist.name}"))
                                            );
                                        }
                                    }
                                }
                            },
                            itemBuilder: (context) => [
                                PopupMenuItem(
                                    value: 'favorite',
                                    child: Row(
                                        children: [
                                            Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                                            const SizedBox(width: 8),
                                            Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                                        ],
                                    ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                    value: 'new_playlist',
                                    child: Row(
                                        children: [
                                            const Icon(Icons.add),
                                            const SizedBox(width: 8),
                                            const Text("Add to new playlist"),
                                        ],
                                    ),
                                ),
                                if (userData.playlists.isNotEmpty) ...[
                                    const PopupMenuDivider(),
                                    ...userData.playlists.map((p) {
                                        final isInPlaylist = p.songs.any((s) => s.filename == song.filename);
                                        return PopupMenuItem(
                                            value: 'toggle_${p.id}',
                                            child: Row(
                                                children: [
                                                    Icon(isInPlaylist ? Icons.remove_circle_outline : Icons.playlist_add),
                                                    const SizedBox(width: 8),
                                                    Text(isInPlaylist ? "Remove from ${p.name}" : "Add to ${p.name}"),
                                                ],
                                            ),
                                        );
                                    }),
                                ],
                            ],
                         );
                      },
                    ),
                    onLongPress: () {
                        showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                                title: const Text("Add to Playlist"),
                                content: SizedBox(
                                    width: double.maxFinite,
                                    child: userData.playlists.isEmpty 
                                        ? const Text("No playlists created yet.") 
                                        : ListView.builder(
                                            shrinkWrap: true,
                                            itemCount: userData.playlists.length,
                                            itemBuilder: (context, index) {
                                                final playlist = userData.playlists[index];
                                                return ListTile(
                                                    title: Text(playlist.name),
                                                    onTap: () {
                                                        ref.read(userDataProvider.notifier).addSongToPlaylist(playlist.id, song.filename);
                                                        Navigator.pop(context);
                                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added to ${playlist.name}")));
                                                    },
                                                );
                                            },
                                        ),
                                ),
                                actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel"))
                                ],
                            ),
                        );
                    },
                    onTap: () {
                      audioManager.player.seek(Duration.zero, index: index);
                      audioManager.player.play();
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      'Error: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.invalidate(songsProvider);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
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
}

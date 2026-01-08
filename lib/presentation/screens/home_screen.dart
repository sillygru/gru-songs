import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../widgets/now_playing_bar.dart';
import 'settings_screen.dart';
import 'playlists_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  void _showSongOptionsMenu(BuildContext context, WidgetRef ref, song, userData) {
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
                  final isSuggestLess = userData.suggestLess.contains(song.filename);
                  final isFavorite = userData.favorites.contains(song.filename);

                  return ListTile(
                    enabled: true,
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
                      song.artist,
                      style: TextStyle(color: isSuggestLess ? Colors.grey : null),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (song.playCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${song.playCount}",
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
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
                    onLongPress: () async {
                       _showSongOptionsMenu(context, ref, song, userData);
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

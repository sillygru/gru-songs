import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/providers.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  final _controller = TextEditingController();

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Playlist"),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: "Playlist Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              if (_controller.text.isNotEmpty) {
                 await ref.read(userDataProvider.notifier).createPlaylist(_controller.text);
                 _controller.clear();
                 if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final songsAsync = ref.watch(songsProvider);
    final apiService = ref.watch(apiServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Playlists"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: userData.playlists.isEmpty
          ? const Center(child: Text("No playlists yet"))
          : ListView.builder(
              itemCount: userData.playlists.length,
              itemBuilder: (context, index) {
                final playlist = userData.playlists[index];
                
                Widget leading = const Icon(Icons.queue_music, size: 40);
                if (playlist.songs.isNotEmpty && songsAsync.hasValue) {
                   final firstSongFilename = playlist.songs.first.filename;
                   final song = songsAsync.value!.firstWhere((s) => s.filename == firstSongFilename, orElse: () => songsAsync.value!.first);
                   if (song.coverUrl != null) {
                      leading = ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: apiService.getFullUrl(song.coverUrl!),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.music_note),
                        ),
                      );
                   }
                }

                return ListTile(
                  leading: leading,
                  title: Text(playlist.name),
                  subtitle: Text("${playlist.songs.length} songs"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                      ),
                    );
                  },
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) async {
                      if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Delete Playlist"),
                            content: Text("Are you sure you want to delete '${playlist.name}'?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true), 
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text("Delete"),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          ref.read(userDataProvider.notifier).deletePlaylist(playlist.id);
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text("Delete Playlist", style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                return ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(playlist.name),
                  subtitle: Text("${playlist.songFilenames.length} songs"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(playlist: playlist),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                       ref.read(userDataProvider.notifier).deletePlaylist(playlist.id);
                    },
                  ),
                );
              },
            ),
    );
  }
}

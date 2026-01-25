import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

class PlaylistSelectionDialog extends ConsumerWidget {
  final String songFilename;

  const PlaylistSelectionDialog({super.key, required this.songFilename});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final playlists = userData.playlists;

    return AlertDialog(
      title: const Text('Add to Playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New Playlist'),
              onTap: () {
                _showNewPlaylistDialog(context, ref, songFilename,
                    popParent: true);
              },
            ),
            const Divider(),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('No playlists yet.', textAlign: TextAlign.center),
              ),
            ...playlists.map((playlist) {
              final alreadyIn =
                  playlist.songs.any((s) => s.songFilename == songFilename);
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songs.length} songs'),
                trailing: alreadyIn ? const Icon(Icons.check, size: 16) : null,
                enabled: !alreadyIn,
                onTap: () {
                  ref
                      .read(userDataProvider.notifier)
                      .addSongToPlaylist(playlist.id, songFilename);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to ${playlist.name}')),
                  );
                },
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  void _showNewPlaylistDialog(
      BuildContext context, WidgetRef ref, String songFilename,
      {bool popParent = false}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Playlist Name'),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref
                  .read(userDataProvider.notifier)
                  .createPlaylist(value.trim(), songFilename);
              Navigator.pop(dialogContext);
              if (popParent) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Created playlist "$value"')),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(userDataProvider.notifier)
                    .createPlaylist(name, songFilename);
                Navigator.pop(dialogContext);
                if (popParent) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created playlist "$name"')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

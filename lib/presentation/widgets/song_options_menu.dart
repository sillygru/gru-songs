import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/song.dart';

void showSongOptionsMenu(
    BuildContext context, WidgetRef ref, String songFilename, String songTitle,
    {Song? song}) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return Consumer(
        builder: (context, ref, child) {
          final userData = ref.watch(userDataProvider);
          final isFavorite = userData.favorites.contains(songFilename);
          final isSuggestLess = userData.suggestLess.contains(songFilename);

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    songTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                if (song != null)
                  ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: const Text("Play Next"),
                    onTap: () {
                      ref.read(audioPlayerManagerProvider).playNext(song);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text("Added to Next Up: ${song.title}"),
                            duration: const Duration(seconds: 1)),
                      );
                    },
                  ),
                ListTile(
                  leading: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : null),
                  title: Text(isFavorite
                      ? "Remove from Favorites"
                      : "Add to Favorites"),
                  onTap: () {
                    ref
                        .read(userDataProvider.notifier)
                        .toggleFavorite(songFilename);
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
                          decoration:
                              const InputDecoration(hintText: "Playlist Name"),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Cancel")),
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, nameController.text),
                              child: const Text("Create")),
                        ],
                      ),
                    );
                    if (newName != null && newName.isNotEmpty) {
                      final newPlaylist = await ref
                          .read(userDataProvider.notifier)
                          .createPlaylist(newName);
                      if (newPlaylist != null) {
                        await ref
                            .read(userDataProvider.notifier)
                            .addSongToPlaylist(newPlaylist.id, songFilename);
                      }
                    }
                  },
                ),
                ...userData.playlists.map((p) {
                  final isInPlaylist =
                      p.songs.any((s) => s.filename == songFilename);
                  if (isInPlaylist) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: Text("Add to ${p.name}"),
                    onTap: () {
                      ref
                          .read(userDataProvider.notifier)
                          .addSongToPlaylist(p.id, songFilename);
                      Navigator.pop(context);
                    },
                  );
                }),
                ...userData.playlists.map((p) {
                  final isInPlaylist =
                      p.songs.any((s) => s.filename == songFilename);
                  if (!isInPlaylist) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: Text("Remove from ${p.name}"),
                    onTap: () {
                      ref
                          .read(userDataProvider.notifier)
                          .removeSongFromPlaylist(p.id, songFilename);
                      Navigator.pop(context);
                    },
                  );
                }),
                ListTile(
                  leading: Icon(Icons.heart_broken,
                      color: isSuggestLess ? Colors.grey : null),
                  title: Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                  onTap: () {
                    ref
                        .read(userDataProvider.notifier)
                        .toggleSuggestLess(songFilename);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

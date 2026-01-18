import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/song.dart';
import 'folder_picker.dart';

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
                if (song != null) ...[
                  ListTile(
                    leading: const Icon(Icons.queue_music),
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
                    leading: const Icon(Icons.drive_file_move_outlined),
                    title: const Text("Move to Folder"),
                    onTap: () async {
                      Navigator.pop(context); // Close bottom sheet
                      
                      final storage = ref.read(storageServiceProvider);
                      final rootPath = await storage.getMusicFolderPath();
                      if (rootPath == null) return;

                      if (context.mounted) {
                        final targetPath = await showFolderPicker(context, rootPath);
                        if (targetPath != null) {
                          try {
                            await ref.read(songsProvider.notifier).moveSong(song, targetPath);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Moved ${song.title} to ${targetPath}")),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error moving song: $e")),
                              );
                            }
                          }
                        }
                      }
                    },
                  ),
                ],
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

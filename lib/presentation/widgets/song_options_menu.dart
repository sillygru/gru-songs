import 'package:flutter/foundation.dart';
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
    builder: (sheetContext) {
      return Consumer(
        builder: (consumerContext, consumerRef, child) {
          final userData = consumerRef.watch(userDataProvider);
          final isFavorite = userData.isFavorite(songFilename);
          final isSuggestLess = userData.isSuggestLess(songFilename);

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
                      Navigator.pop(sheetContext);
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
                      if (kDebugMode) {
                        debugPrint("UI: Move Song tapped for ${song.title}");
                      }
                      Navigator.pop(sheetContext); // Close bottom sheet

                      final storage = ref.read(storageServiceProvider);
                      final rootPath = await storage.getMusicFolderPath();
                      if (rootPath == null) {
                        if (kDebugMode)
                          debugPrint("UI: ERROR - rootPath is null");
                        return;
                      }

                      if (context.mounted) {
                        if (kDebugMode)
                          debugPrint("UI: Opening folder picker...");
                        final targetPath =
                            await showFolderPicker(context, rootPath);
                        if (targetPath != null) {
                          if (kDebugMode) {
                            debugPrint("UI: Selected target path: $targetPath");
                          }
                          try {
                            await ref
                                .read(songsProvider.notifier)
                                .moveSong(song, targetPath);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Moved ${song.title} to $targetPath")),
                              );
                            }
                          } catch (e) {
                            if (kDebugMode)
                              debugPrint("UI: ERROR during move: $e");
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text("Error moving song: $e")),
                              );
                            }
                          }
                        } else {
                          if (kDebugMode)
                            debugPrint("UI: Folder picker cancelled");
                        }
                      } else {
                        if (kDebugMode) {
                          debugPrint(
                              "UI: ERROR - context not mounted after pop");
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
                    Navigator.pop(sheetContext);
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
                    Navigator.pop(sheetContext);
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

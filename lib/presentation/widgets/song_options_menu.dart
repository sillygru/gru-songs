import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
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
                        if (kDebugMode) {
                          debugPrint("UI: ERROR - rootPath is null");
                        }
                        return;
                      }

                      if (context.mounted) {
                        if (kDebugMode) {
                          debugPrint("UI: Opening folder picker...");
                        }
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
                            if (kDebugMode) {
                              debugPrint("UI: ERROR during move: $e");
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text("Error moving song: $e")),
                              );
                            }
                          }
                        } else {
                          if (kDebugMode) {
                            debugPrint("UI: Folder picker cancelled");
                          }
                        }
                      } else {
                        if (kDebugMode) {
                          debugPrint(
                              "UI: ERROR - context not mounted after pop");
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text("Rename"),
                    onTap: () async {
                      Navigator.pop(sheetContext);

                      // 1. Ask what to rename
                      final String? renameType = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("What would you like to rename?"),
                          content: const Text(
                              "Choose between editing the metadata title or the physical file name."),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, "title"),
                              child: const Text("Song Title"),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, "filename"),
                              child: const Text("File Name"),
                            ),
                          ],
                        ),
                      );

                      if (renameType == null) return;

                      if (renameType == "title") {
                        // RENAME TITLE (Metadata only)

                        if (context.mounted) {
                          final String? newTitle = await _showRenameDialog(
                              context, song.title, "Edit Song Title");

                          if (newTitle != null &&
                              newTitle.isNotEmpty &&
                              newTitle != song.title) {
                            int deviceCount = 0;

                            final storage = ref.read(storageServiceProvider);

                            if (!await storage.getIsLocalMode()) {
                              if (context.mounted) {
                                deviceCount =
                                    await _showDeviceCountDialog(context);
                              }
                            }

                            try {
                              await ref
                                  .read(songsProvider.notifier)
                                  .updateSongTitle(song, newTitle,
                                      deviceCount: deviceCount);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text("Title updated to $newTitle")),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Error: $e")),
                                );
                              }
                            }
                          }
                        }
                      } else {
                        // RENAME FILENAME (FileSystem + Sync)
                        if (context.mounted) {
                          final String? newFilename = await _showRenameDialog(
                              context,
                              p.basenameWithoutExtension(song.filename),
                              "Rename File");

                          if (newFilename != null &&
                              newFilename.isNotEmpty &&
                              newFilename !=
                                  p.basenameWithoutExtension(song.filename)) {
                            int deviceCount = 0;
                            final storage = ref.read(storageServiceProvider);
                            if (!await storage.getIsLocalMode()) {
                              if (context.mounted) {
                                deviceCount =
                                    await _showDeviceCountDialog(context);
                              }
                            }

                            try {
                              await ref.read(songsProvider.notifier).renameSong(
                                  song, newFilename,
                                  deviceCount: deviceCount);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text("File renamed to $newFilename")),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Error: $e")),
                                );
                              }
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

Future<String?> _showRenameDialog(
    BuildContext context, String currentTitle, String dialogTitle) {
  final controller = TextEditingController(text: currentTitle);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(dialogTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: "New Title"),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text("Rename"),
        ),
      ],
    ),
  );
}

Future<int> _showDeviceCountDialog(BuildContext context) async {
  int count = 0;
  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text("Sync to other devices?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "How many other devices do you want to sync this rename to?"),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: count > 0 ? () => setState(() => count--) : null,
                ),
                Text(count.toString(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: count < 5 ? () => setState(() => count++) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "Warning: Stats will be split if you don't rename the file on other devices.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              count = 0;
              Navigator.pop(context);
            },
            child: const Text("Don't Sync"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Set Sync"),
          ),
        ],
      ),
    ),
  );
  return count;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/song.dart';
import 'folder_picker.dart';
import '../screens/edit_metadata_screen.dart';
import 'playlist_selector_screen.dart';

void showSongOptionsMenu(
    BuildContext context, WidgetRef ref, String songFilename, String songTitle,
    {Song? song, String? playlistId}) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return Consumer(
        builder: (consumerContext, consumerRef, child) {
          final userData = consumerRef.watch(userDataProvider);
          final isFavorite = userData.isFavorite(songFilename);
          final isSuggestLess = userData.isSuggestLess(songFilename);

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: SingleChildScrollView(
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
                                content:
                                    Text("Added to Next Up: ${song.title}"),
                                duration: const Duration(seconds: 1)),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.drive_file_move_outlined),
                        title: const Text("Move to Folder"),
                        onTap: () async {
                          if (kDebugMode) {
                            debugPrint(
                                "UI: Move Song tapped for ${song.title}");
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
                                debugPrint(
                                    "UI: Selected target path: $targetPath");
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
                        leading: const Icon(Icons.playlist_add),
                        title: const Text("Add to Playlist"),
                        onTap: () {
                          Navigator.pop(sheetContext);

                          final playlists =
                              ref.read(userDataProvider).playlists;
                          final sorted = List.of(playlists)
                            ..sort(
                                (a, b) => b.updatedAt.compareTo(a.updatedAt));

                          if (sorted.isEmpty) {
                            showPlaylistSelector(context, ref, songFilename);
                          } else {
                            final latest = sorted.first;
                            if (latest.songs
                                .any((s) => s.songFilename == songFilename)) {
                              showPlaylistSelector(context, ref, songFilename);
                            } else {
                              ref
                                  .read(userDataProvider.notifier)
                                  .addSongToPlaylist(latest.id, songFilename);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Added to ${latest.name}"),
                                  action: SnackBarAction(
                                      label: "Change",
                                      onPressed: () {
                                        showPlaylistSelector(
                                            context, ref, songFilename);
                                      }),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_add_circle_outlined),
                        title: const Text("Add to New Playlist"),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          // Trigger new playlist dialog directly

                          final controller = TextEditingController();
                          showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('New Playlist'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                    hintText: 'Playlist Name'),
                                autofocus: true,
                                onSubmitted: (value) {
                                  if (value.trim().isNotEmpty) {
                                    ref
                                        .read(userDataProvider.notifier)
                                        .createPlaylist(
                                            value.trim(), songFilename);
                                    Navigator.pop(dialogContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Created playlist "$value"')),
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Created playlist "$name"')),
                                      );
                                    }
                                  },
                                  child: const Text('Create'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (playlistId != null)
                        ListTile(
                          leading: const Icon(Icons.playlist_remove,
                              color: Colors.red),
                          title: const Text("Remove from current playlist",
                              style: TextStyle(color: Colors.red)),
                          onTap: () {
                            ref
                                .read(userDataProvider.notifier)
                                .removeSongFromPlaylist(
                                    playlistId, songFilename);
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text("Removed $songTitle from playlist"),
                                action: SnackBarAction(
                                  label: "Change",
                                  onPressed: () {
                                    showPlaylistSelector(
                                        context, ref, songFilename);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text("Edit Metadata"),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditMetadataScreen(song: song),
                            ),
                          );
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
                      title:
                          Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                      onTap: () {
                        ref
                            .read(userDataProvider.notifier)
                            .toggleSuggestLess(songFilename);
                        Navigator.pop(sheetContext);
                      },
                    ),
                    if (song != null)
                      ListTile(
                        leading:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text("Delete",
                            style: TextStyle(color: Colors.red)),
                        onTap: () async {
                          Navigator.pop(sheetContext);

                          final String? action = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Delete Song"),
                              content: const Text(
                                  "Choose whether to just hide this song from your library or delete the physical file from your device."),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, "hide"),
                                  child: const Text("Remove from library"),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, "delete"),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: const Text("Delete file"),
                                ),
                              ],
                            ),
                          );

                          if (action == "hide") {
                            await ref
                                .read(songsProvider.notifier)
                                .hideSong(song);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Removed ${song.title} from library")),
                              );
                            }
                          } else if (action == "delete") {
                            if (!context.mounted) return;
                            final bool confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Confirm Delete"),
                                    content: Text(
                                        "Are you sure you want to permanently delete '${song.title}' from your device? This cannot be undone."),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.red),
                                        child: const Text("Delete Permanently"),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;

                            if (confirm) {
                              try {
                                await ref
                                    .read(songsProvider.notifier)
                                    .deleteSongFile(song);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text("Deleted ${song.title}")),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text("Error deleting file: $e")),
                                  );
                                }
                              }
                            }
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

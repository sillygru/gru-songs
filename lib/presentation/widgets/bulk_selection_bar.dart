import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/quick_action_config.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/selection_provider.dart';
import '../screens/bulk_metadata_screen.dart';
import '../screens/edit_metadata_screen.dart';
import 'playlist_selector_screen.dart';
import 'folder_picker.dart';

class BulkSelectionBar extends ConsumerWidget {
  const BulkSelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    if (!selectionState.isSelectionMode) return const SizedBox.shrink();

    final settings = ref.watch(settingsProvider);
    final enabledActions = settings.quickActionConfig.enabledActions;
    final actionOrder = settings.quickActionConfig.actionOrder;

    final selectedCount = selectionState.selectedFilenames.length;
    final allSongs = ref.watch(songsProvider).value ?? [];
    final selectedSongs = allSongs
        .where((s) => selectionState.selectedFilenames.contains(s.filename))
        .toList();

    final currentSong =
        ref.read(audioPlayerManagerProvider).currentSongNotifier.value;
    final isCurrentlyPlaying =
        selectedSongs.any((s) => s.filename == currentSong?.filename);

    final buttons = <Widget>[];
    for (final action in actionOrder) {
      if (!enabledActions.contains(action)) continue;

      Widget? button;
      switch (action) {
        case QuickAction.toggleFavorite:
          button =
              _buildFavoriteButton(context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.addToPlaylist:
          button =
              _buildPlaylistButton(context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.editMetadata:
          button = _buildMetadataButton(
              context, ref, selectedSongs, selectedCount, isCurrentlyPlaying);
          break;
        case QuickAction.hide:
          button = _buildHideButton(context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.delete:
          button =
              _buildDeleteButton(context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.playNext:
          button =
              _buildPlayNextButton(context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.moveToFolder:
          button = _buildMoveToFolderButton(
              context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.toggleSuggestLess:
          button = _buildSuggestLessButton(
              context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.addToNewPlaylist:
          button = _buildAddToNewPlaylistButton(
              context, ref, selectedSongs, selectedCount);
          break;
        case QuickAction.goToAlbum:
        case QuickAction.goToArtist:
          break;
      }
      if (button != null) buttons.add(button);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(selectionProvider.notifier).exitSelectionMode(),
                ),
                Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final allFilenames =
                        allSongs.map((s) => s.filename).toList();
                    ref
                        .read(selectionProvider.notifier)
                        .selectAll(allFilenames);
                  },
                  child: const Text('Select All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buttons,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    final userData = ref.read(userDataProvider);
    final allFavorited = songs.every((s) => userData.isFavorite(s.filename));

    return _ActionButton(
      icon: allFavorited ? Icons.favorite : Icons.favorite_border,
      label: allFavorited ? 'Unfavorite' : 'Favorite',
      color: allFavorited ? Colors.red : null,
      onTap: () {
        final filenames = songs.map((s) => s.filename).toList();
        ref
            .read(userDataProvider.notifier)
            .bulkToggleFavorite(filenames, !allFavorited);
        ref.read(selectionProvider.notifier).exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(allFavorited
                  ? 'Removed ${songs.length} songs from favorites'
                  : 'Added ${songs.length} songs to favorites')),
        );
      },
    );
  }

  Widget _buildPlaylistButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.playlist_add,
      label: 'Playlist',
      onTap: () {
        final filenames = songs.map((s) => s.filename).toList();
        final playlists = ref
            .read(userDataProvider)
            .playlists
            .where((p) => !p.isRecommendation)
            .toList();
        final sorted = List.of(playlists)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (sorted.isEmpty) {
          showBulkPlaylistSelector(context, ref, filenames);
        } else {
          final latest = sorted.first;
          ref
              .read(userDataProvider.notifier)
              .bulkAddSongsToPlaylist(latest.id, filenames);
          ref.read(selectionProvider.notifier).exitSelectionMode();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Added ${songs.length} songs to ${latest.name}"),
              action: SnackBarAction(
                label: "Change",
                onPressed: () {
                  showBulkPlaylistSelector(context, ref, filenames);
                },
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildMetadataButton(BuildContext context, WidgetRef ref,
      List<Song> songs, int count, bool isCurrentlyPlaying) {
    return _ActionButton(
      icon: Icons.edit,
      label: 'Metadata',
      onTap: isCurrentlyPlaying
          ? null
          : () {
              if (count == 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditMetadataScreen(song: songs[0]),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BulkMetadataScreen(songs: songs),
                  ),
                );
              }
            },
    );
  }

  Widget _buildHideButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.visibility_off,
      label: 'Hide',
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hide Songs'),
            content: Text('Hide ${songs.length} selected songs from library?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(userDataProvider.notifier).bulkHide(
                        songs.map((s) => s.filename).toList(),
                        true,
                      );
                  ref.read(selectionProvider.notifier).exitSelectionMode();
                  Navigator.pop(ctx);
                },
                child: const Text('Hide'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeleteButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.delete_outline,
      label: 'Delete',
      color: Colors.redAccent,
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Files'),
            content: Text(
              'Permanently delete ${songs.length} files from storage? This cannot be undone.',
              style: const TextStyle(color: Colors.redAccent),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  ref.read(songsProvider.notifier).bulkDeleteSongs(songs);
                  ref.read(selectionProvider.notifier).exitSelectionMode();
                  Navigator.pop(ctx);
                },
                child: const Text('Delete Permanently'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayNextButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.queue,
      label: 'Play Next',
      onTap: () {
        final orderedFilenames =
            ref.read(selectionProvider.notifier).getOrderedSelection();
        final audioManager = ref.read(audioPlayerManagerProvider);

        for (final filename in orderedFilenames.reversed) {
          final song = songs.firstWhere((s) => s.filename == filename);
          audioManager.playNext(song);
        }

        ref.read(selectionProvider.notifier).exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${songs.length} songs to queue')),
        );
      },
    );
  }

  Widget _buildMoveToFolderButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.drive_file_move_outlined,
      label: 'Move',
      onTap: () async {
        if (kDebugMode) {
          debugPrint("UI: Move Songs tapped for ${songs.length} songs");
        }

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
          final targetPath = await showFolderPicker(context, rootPath);
          if (targetPath != null) {
            if (kDebugMode) {
              debugPrint("UI: Selected target path: $targetPath");
            }
            try {
              for (final song in songs) {
                await ref
                    .read(songsProvider.notifier)
                    .moveSong(song, targetPath);
              }
              ref.read(selectionProvider.notifier).exitSelectionMode();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text("Moved ${songs.length} songs to $targetPath")),
                );
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint("UI: ERROR during move: $e");
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error moving songs: $e")),
                );
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint("UI: Folder picker cancelled");
            }
          }
        }
      },
    );
  }

  Widget _buildSuggestLessButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    final userData = ref.read(userDataProvider);
    final allSuggestLess =
        songs.every((s) => userData.isSuggestLess(s.filename));

    return _ActionButton(
      icon: Icons.heart_broken,
      label: allSuggestLess ? 'Suggest More' : 'Suggest Less',
      color: allSuggestLess ? Colors.grey : null,
      onTap: () {
        final filenames = songs.map((s) => s.filename).toList();
        ref
            .read(userDataProvider.notifier)
            .bulkToggleSuggestLess(filenames, !allSuggestLess);
        ref.read(selectionProvider.notifier).exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(allSuggestLess
                  ? 'Will suggest ${songs.length} songs more'
                  : 'Will suggest ${songs.length} songs less')),
        );
      },
    );
  }

  Widget _buildAddToNewPlaylistButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.playlist_add_circle_outlined,
      label: 'New Playlist',
      onTap: () {
        final controller = TextEditingController();
        final filenames = songs.map((s) => s.filename).toList();

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
                  ref.read(userDataProvider.notifier).createPlaylist(
                      value.trim(),
                      filenames.isNotEmpty ? filenames.first : null);
                  if (filenames.length > 1) {
                    final playlists = ref.read(userDataProvider).playlists;
                    final newPlaylist =
                        playlists.lastWhere((p) => p.name == value.trim());
                    ref.read(userDataProvider.notifier).bulkAddSongsToPlaylist(
                          newPlaylist.id,
                          filenames.skip(1).toList(),
                        );
                  }
                  Navigator.pop(dialogContext);
                  ref.read(selectionProvider.notifier).exitSelectionMode();
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
                    ref.read(userDataProvider.notifier).createPlaylist(
                        name, filenames.isNotEmpty ? filenames.first : null);
                    if (filenames.length > 1) {
                      final playlists = ref.read(userDataProvider).playlists;
                      final newPlaylist =
                          playlists.lastWhere((p) => p.name == name);
                      ref
                          .read(userDataProvider.notifier)
                          .bulkAddSongsToPlaylist(
                            newPlaylist.id,
                            filenames.skip(1).toList(),
                          );
                    }
                    Navigator.pop(dialogContext);
                    ref.read(selectionProvider.notifier).exitSelectionMode();
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
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final isDisabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDisabled
                  ? effectiveColor.withValues(alpha: 0.3)
                  : effectiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDisabled
                    ? effectiveColor.withValues(alpha: 0.3)
                    : effectiveColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

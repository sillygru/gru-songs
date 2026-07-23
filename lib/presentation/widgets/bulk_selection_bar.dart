import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/quick_action_config.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/selection_provider.dart';
import '../screens/bulk_metadata_screen.dart';
import '../screens/edit_metadata_screen.dart';
import 'playlist_selector_screen.dart';
import 'folder_picker.dart';
import '../tokens/app_tokens.dart';
import '../components/app_dialog.dart';
import '../components/app_feedback.dart';
import '../components/pressable.dart';
import '../routes/app_page_route.dart';

class BulkSelectionBar extends ConsumerWidget {
  const BulkSelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    if (!selectionState.isSelectionMode) return const SizedBox.shrink();

    final accent = AppTokens.accentOf(context, ref);
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
        case QuickAction.share:
          button =
              _buildShareButton(context, ref, selectedSongs, selectedCount);
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
        color: Color.alphaBlend(
          AppTokens.surface(2),
          Theme.of(context).scaffoldBackgroundColor,
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rLg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Done',
                  onPressed: () =>
                      ref.read(selectionProvider.notifier).exitSelectionMode(),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '$selectedCount',
                      style: AppTokens.paneTitle(context).copyWith(
                        color: accent,
                        fontSize: 18,
                      ),
                    ),
                    TextSpan(
                      text: ' selected',
                      style:
                          AppTokens.paneTitle(context).copyWith(fontSize: 18),
                    ),
                  ]),
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
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: const Text('Select all'),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s2),
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
      icon:
          allFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: allFavorited ? 'Unfavorite' : 'Favorite',
      color: allFavorited ? AppTokens.danger : null,
      onTap: () {
        if (!context.mounted) return;
        final filenames = songs.map((s) => s.filename).toList();
        ref
            .read(userDataProvider.notifier)
            .bulkToggleFavorite(filenames, !allFavorited);
        ref.read(selectionProvider.notifier).exitSelectionMode();
        if (!context.mounted) return;
        appSnack(
            context,
            allFavorited
                ? 'Removed ${songs.length} songs from favorites'
                : 'Added ${songs.length} songs to favorites');
      },
    );
  }

  Widget _buildPlaylistButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.playlist_add_rounded,
      label: 'Playlist',
      onTap: () {
        if (!context.mounted) return;
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
          if (!context.mounted) return;

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

  Widget _buildShareButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.ios_share_rounded,
      label: 'Share',
      onTap: () {
        if (!context.mounted) return;
        final xFiles = songs.map((s) => XFile(s.url)).toList();
        final text = songs.length == 1
            ? '${songs[0].title} by ${songs[0].artist}'
            : '${songs.length} songs';
        Share.shareXFiles(xFiles, text: text);
        ref.read(selectionProvider.notifier).exitSelectionMode();
      },
    );
  }

  Widget _buildMetadataButton(BuildContext context, WidgetRef ref,
      List<Song> songs, int count, bool isCurrentlyPlaying) {
    return _ActionButton(
      icon: Icons.edit_rounded,
      label: 'Metadata',
      onTap: isCurrentlyPlaying
          ? null
          : () {
              if (count == 1) {
                context.pushApp(EditMetadataScreen(song: songs[0]));
              } else {
                context.pushApp(BulkMetadataScreen(songs: songs));
              }
            },
    );
  }

  Widget _buildHideButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.visibility_off_rounded,
      label: 'Hide',
      onTap: () async {
        final confirmed = await showAppConfirm(
          context,
          title: 'Hide Songs',
          message: 'Hide ${songs.length} selected songs from library?',
          confirmLabel: 'Hide',
          isDanger: true,
        );
        if (confirmed == true) {
          ref.read(userDataProvider.notifier).bulkHide(
                songs.map((s) => s.filename).toList(),
                true,
              );
          ref.read(selectionProvider.notifier).exitSelectionMode();
        }
      },
    );
  }

  Widget _buildDeleteButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.delete_outline_rounded,
      label: 'Delete',
      color: AppTokens.danger,
      onTap: () async {
        final confirmed = await showAppConfirm(
          context,
          title: 'Delete Files',
          message:
              'Permanently delete ${songs.length} files from storage? This cannot be undone.',
          confirmLabel: 'Delete Permanently',
          isDanger: true,
        );
        if (confirmed == true) {
          ref.read(songsProvider.notifier).bulkDeleteSongs(songs);
          ref.read(selectionProvider.notifier).exitSelectionMode();
        }
      },
    );
  }

  Widget _buildPlayNextButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.queue_music_rounded,
      label: 'Play Next',
      onTap: () {
        if (!context.mounted) return;
        final orderedFilenames =
            ref.read(selectionProvider.notifier).getOrderedSelection();
        final audioManager = ref.read(audioPlayerManagerProvider);

        for (final filename in orderedFilenames.reversed) {
          final song = songs.firstWhere((s) => s.filename == filename);
          audioManager.playNext(song);
        }

        ref.read(selectionProvider.notifier).exitSelectionMode();
        if (!context.mounted) return;
        appSnack(context, 'Added ${songs.length} songs to queue');
      },
    );
  }

  Widget _buildMoveToFolderButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.drive_file_move_rounded,
      label: 'Move',
      onTap: () async {
        if (kDebugMode) {
          debugPrint("UI: Move Songs tapped for ${songs.length} songs");
        }

        if (!context.mounted) return;
        final storage = ref.read(storageServiceProvider);
        final rootPath = await storage.getMusicFolderPath();
        if (rootPath == null) {
          if (kDebugMode) {
            debugPrint("UI: rootPath is null");
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
              if (!context.mounted) return;
              if (context.mounted) {
                appSnack(context, "Moved ${songs.length} songs to $targetPath");
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint("UI: ERROR during move: $e");
              }
              if (context.mounted) {
                appSnack(context, "Error moving songs: $e");
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
      icon: Icons.heart_broken_rounded,
      label: allSuggestLess ? 'Suggest More' : 'Suggest Less',
      color: allSuggestLess ? AppTokens.fgTertiary : null,
      onTap: () {
        if (!context.mounted) return;
        final filenames = songs.map((s) => s.filename).toList();
        ref
            .read(userDataProvider.notifier)
            .bulkToggleSuggestLess(filenames, !allSuggestLess);
        ref.read(selectionProvider.notifier).exitSelectionMode();
        if (!context.mounted) return;
        appSnack(
            context,
            allSuggestLess
                ? 'Will suggest ${songs.length} songs more'
                : 'Will suggest ${songs.length} songs less');
      },
    );
  }

  Widget _buildAddToNewPlaylistButton(
      BuildContext context, WidgetRef ref, List<Song> songs, int count) {
    return _ActionButton(
      icon: Icons.playlist_add_circle_outlined,
      label: 'New Playlist',
      onTap: () async {
        final filenames = songs.map((s) => s.filename).toList();
        final name = await showAppTextPrompt(
          context,
          title: 'New Playlist',
          hintText: 'Playlist name',
          confirmLabel: 'Create',
        );
        if (name == null) return;

        ref.read(userDataProvider.notifier).createPlaylist(
            name, filenames.isNotEmpty ? filenames.first : null);
        if (filenames.length > 1) {
          final playlists = ref.read(userDataProvider).playlists;
          final newPlaylist = playlists.lastWhere((p) => p.name == name);
          ref.read(userDataProvider.notifier).bulkAddSongsToPlaylist(
                newPlaylist.id,
                filenames.skip(1).toList(),
              );
        }
        ref.read(selectionProvider.notifier).exitSelectionMode();
        if (!context.mounted) return;
        appSnack(context, 'Created playlist "$name"');
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
    final effectiveColor = color ?? AppTokens.fg(AppTokens.aSecondary);
    final isDisabled = onTap == null;
    final tint =
        isDisabled ? effectiveColor.withValues(alpha: 0.3) : effectiveColor;

    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTokens.surface(1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: tint),
            ),
            const SizedBox(height: AppTokens.s1 + 2),
            Text(
              label,
              style: AppTokens.meta(context).copyWith(color: tint),
            ),
          ],
        ),
      ),
    );
  }
}

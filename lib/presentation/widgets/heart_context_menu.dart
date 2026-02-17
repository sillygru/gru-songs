import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/playlist.dart';
import 'playlist_selector_screen.dart';

void showHeartContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required String songFilename,
  required String songTitle,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Consumer(
        builder: (context, ref, child) {
          final userData = ref.watch(userDataProvider);
          final isFavorite = userData.isFavorite(songFilename);
          final isSuggestLess = userData.isSuggestLess(songFilename);
          final playlists =
              userData.playlists.where((p) => !p.isRecommendation).toList();

          // Find the playlist this song was most recently added to
          Playlist? latestPlaylistWithSong;
          double latestAddedAt = -1;

          for (final pl in playlists) {
            for (final ps in pl.songs) {
              if (ps.songFilename == songFilename) {
                if (ps.addedAt > latestAddedAt) {
                  latestAddedAt = ps.addedAt;
                  latestPlaylistWithSong = pl;
                }
              }
            }
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
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
                    ListTile(
                      leading: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.red : null,
                      ),
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
                      title: const Text("Add to Playlist"),
                      onTap: () {
                        Navigator.pop(context);
                        _handleAddToPlaylist(context, ref, songFilename);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.playlist_add_circle_outlined),
                      title: const Text("Add to New Playlist"),
                      onTap: () {
                        Navigator.pop(context);
                        _showNewPlaylistDialog(context, ref, songFilename);
                      },
                    ),
                    if (latestPlaylistWithSong != null)
                      ListTile(
                        leading: const Icon(Icons.playlist_remove,
                            color: Colors.red),
                        title: Text(
                            "Remove from ${latestPlaylistWithSong.name}",
                            style: const TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(context);
                          _handleRemoveFromPlaylist(context, ref, songFilename,
                              latestPlaylistWithSong!);
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
                        Navigator.pop(context);
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

void _handleAddToPlaylist(
    BuildContext context, WidgetRef ref, String songFilename) {
  final playlists = ref
      .read(userDataProvider)
      .playlists
      .where((p) => !p.isRecommendation)
      .toList();
  final sorted = List.of(playlists)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  if (sorted.isEmpty) {
    showPlaylistSelector(context, ref, songFilename);
  } else {
    final latest = sorted.first;
    // If already in latest, show picker immediately
    if (latest.songs.any((s) => s.songFilename == songFilename)) {
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
              // Note: We don't remove from latest here because "Change" should allow managing all
              showPlaylistSelector(context, ref, songFilename);
            },
          ),
        ),
      );
    }
  }
}

void _handleRemoveFromPlaylist(BuildContext context, WidgetRef ref,
    String songFilename, Playlist playlist) {
  ref
      .read(userDataProvider.notifier)
      .removeSongFromPlaylist(playlist.id, songFilename);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("Removed from ${playlist.name}"),
      action: SnackBarAction(
        label: "Change",
        onPressed: () {
          // Add it back? Or just show picker.
          // The user said: "with the dialog asking us if we want to change"
          // Let's just show the picker.
          showPlaylistSelector(context, ref, songFilename);
        },
      ),
    ),
  );
}

void _showNewPlaylistDialog(
    BuildContext context, WidgetRef ref, String songFilename) {
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

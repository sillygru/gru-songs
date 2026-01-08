import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../screens/player_screen.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerManagerProvider).player;

    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();

        final metadata = state.currentSource?.tag as MediaItem?;
        if (metadata == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const PlayerScreen(),
            );
          },
          child: Container(
            height: 70,
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: metadata.artUri.toString(),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        metadata.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final userData = ref.watch(userDataProvider);
                    final isFavorite = userData.favorites.contains(metadata.id);
                    return PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) async {
                            if (value == 'favorite') {
                                ref.read(userDataProvider.notifier).toggleFavorite(metadata.id);
                            } else if (value == 'new_playlist') {
                                final nameController = TextEditingController();
                                final newName = await showDialog<String>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                        title: const Text("New Playlist"),
                                        content: TextField(
                                            controller: nameController,
                                            decoration: const InputDecoration(hintText: "Playlist Name"),
                                            autofocus: true,
                                        ),
                                        actions: [
                                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                                            TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text("Create")),
                                        ],
                                    ),
                                );
                                
                                if (newName != null && newName.isNotEmpty) {
                                    final newPlaylist = await ref.read(userDataProvider.notifier).createPlaylist(newName);
                                    if (newPlaylist != null) {
                                        await ref.read(userDataProvider.notifier).addSongToPlaylist(newPlaylist.id, metadata.id);
                                        if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text("Created and added to $newName"))
                                            );
                                        }
                                    }
                                }
                            } else if (value.startsWith('toggle_')) {
                                final playlistId = value.replaceFirst('toggle_', '');
                                final playlist = userData.playlists.firstWhere((p) => p.id == playlistId);
                                final exists = playlist.songs.any((s) => s.filename == metadata.id);
                                
                                if (exists) {
                                    await ref.read(userDataProvider.notifier).removeSongFromPlaylist(playlistId, metadata.id);
                                    if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Removed from ${playlist.name}"))
                                        );
                                    }
                                } else {
                                    await ref.read(userDataProvider.notifier).addSongToPlaylist(playlistId, metadata.id);
                                    if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Added to ${playlist.name}"))
                                        );
                                    }
                                }
                            }
                        },
                        itemBuilder: (context) => [
                            PopupMenuItem(
                                value: 'favorite',
                                child: Row(
                                    children: [
                                        Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                                        const SizedBox(width: 8),
                                        Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                                    ],
                                ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                                value: 'new_playlist',
                                child: Row(
                                    children: [
                                        const Icon(Icons.add),
                                        const SizedBox(width: 8),
                                        const Text("Add to new playlist"),
                                    ],
                                ),
                            ),
                            if (userData.playlists.isNotEmpty) ...[
                                const PopupMenuDivider(),
                                ...userData.playlists.map((p) {
                                    final isInPlaylist = p.songs.any((s) => s.filename == metadata.id);
                                    return PopupMenuItem(
                                        value: 'toggle_${p.id}',
                                        child: Row(
                                            children: [
                                                Icon(isInPlaylist ? Icons.remove_circle_outline : Icons.playlist_add),
                                                const SizedBox(width: 8),
                                                Text(isInPlaylist ? "Remove from ${p.name}" : "Add to ${p.name}"),
                                            ],
                                        ),
                                    );
                                }),
                            ],
                        ],
                    );
                  },
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final playing = playerState?.playing ?? false;
                    final processingState = playerState?.processingState;

                    if (processingState == ProcessingState.buffering) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }

                    return IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playing ? player.pause : player.play,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: player.hasNext ? player.seekToNext : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

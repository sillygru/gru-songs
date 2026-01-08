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
                            } else if (value == 'suggest_less') {
                                ref.read(userDataProvider.notifier).toggleSuggestLess(metadata.id);
                            } else if (value.startsWith('add_to_')) {
                                final pid = value.replaceFirst('add_to_', '');
                                await ref.read(userDataProvider.notifier).addSongToPlaylist(pid, metadata.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to playlist")));
                                }
                            } else if (value.startsWith('remove_from_')) {
                                final pid = value.replaceFirst('remove_from_', '');
                                await ref.read(userDataProvider.notifier).removeSongFromPlaylist(pid, metadata.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Removed from playlist")));
                                }
                            }
                        },
                        itemBuilder: (context) {
                          final List<PopupMenuEntry<String>> items = [];
                          final isSuggestLess = userData.suggestLess.contains(metadata.id);

                          // 1. Favorite
                          items.add(PopupMenuItem(
                            value: 'favorite',
                            child: Row(
                              children: [
                                Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                                const SizedBox(width: 8),
                                Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                              ],
                            ),
                          ));

                          // 2. Add to [playlist]
                          for (final p in userData.playlists) {
                            if (!p.songs.any((s) => s.filename == metadata.id)) {
                              items.add(PopupMenuItem(
                                value: 'add_to_${p.id}',
                                child: Row(
                                  children: [
                                    const Icon(Icons.playlist_add),
                                    const SizedBox(width: 8),
                                    Text("Add to ${p.name}"),
                                  ],
                                ),
                              ));
                            }
                          }

                          // 3. Remove from [playlist]
                          for (final p in userData.playlists) {
                            if (p.songs.any((s) => s.filename == metadata.id)) {
                              items.add(PopupMenuItem(
                                value: 'remove_from_${p.id}',
                                child: Row(
                                  children: [
                                    const Icon(Icons.remove_circle_outline),
                                    const SizedBox(width: 8),
                                    Text("Remove from ${p.name}"),
                                  ],
                                ),
                              ));
                            }
                          }

                          // 4. Suggest less
                          items.add(PopupMenuItem(
                            value: 'suggest_less',
                            child: Row(
                              children: [
                                Icon(isSuggestLess ? Icons.thumb_down : Icons.thumb_down_outlined, color: isSuggestLess ? Colors.orange : null),
                                const SizedBox(width: 8),
                                Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                              ],
                            ),
                          ));

                          return items;
                        },
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

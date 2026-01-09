import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../screens/player_screen.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  void _showSongOptionsMenu(BuildContext context, WidgetRef ref, MediaItem metadata, UserDataState userData) {
    final isFavorite = userData.favorites.contains(metadata.id);
    final isSuggestLess = userData.suggestLess.contains(metadata.id);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                title: Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleFavorite(metadata.id);
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
                    }
                  }
                },
              ),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == metadata.id);
                if (isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text("Add to ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).addSongToPlaylist(p.id, metadata.id);
                    Navigator.pop(context);
                  },
                );
              }),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == metadata.id);
                if (!isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text("Remove from ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).removeSongFromPlaylist(p.id, metadata.id);
                    Navigator.pop(context);
                  },
                );
              }),
              ListTile(
                leading: Icon(isSuggestLess ? Icons.thumb_up : Icons.thumb_down_outlined, color: isSuggestLess ? Colors.orange : null),
                title: Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleSuggestLess(metadata.id);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerManagerProvider).player;
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final isIPad = !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.shortestSide >= 600;

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
            height: (isDesktop || isIPad) ? 100 : 70,
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            metadata.artist ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isDesktop || isIPad) ...[
                      const Icon(Icons.volume_down, size: 20),
                      SizedBox(
                        width: 120,
                        child: StreamBuilder<double>(
                          stream: player.volumeStream,
                          builder: (context, snapshot) {
                            return Slider(
                              value: snapshot.data ?? 1.0,
                              onChanged: player.setVolume,
                            );
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up, size: 20),
                      const SizedBox(width: 12),
                    ],
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final userData = ref.watch(userDataProvider);
                            final isFavorite = userData.favorites.contains(metadata.id);
                            final isSuggestLess = userData.suggestLess.contains(metadata.id);
                            
                            return GestureDetector(
                              onLongPress: () => _showSongOptionsMenu(context, ref, metadata, userData),
                              child: IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: Icon(
                                  isSuggestLess 
                                    ? Icons.heart_broken 
                                    : (isFavorite ? Icons.favorite : Icons.favorite_border),
                                  size: 22,
                                ),
                                color: isSuggestLess ? Colors.grey : (isFavorite ? Colors.red : null),
                                onPressed: () {
                                  ref.read(userDataProvider.notifier).toggleFavorite(metadata.id);
                                },
                              ),
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
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow, size: 28),
                              onPressed: playing ? player.pause : player.play,
                            );
                          },
                        ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                          icon: const Icon(Icons.skip_next, size: 24),
                          onPressed: player.hasNext ? player.seekToNext : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gru_image.dart';
import '../../providers/providers.dart';
import '../screens/player_screen.dart';
import 'song_options_menu.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerManagerProvider).player;
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final isIPad = !kIsWeb &&
        Platform.isIOS &&
        MediaQuery.of(context).size.shortestSide >= 600;

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
            height: (isDesktop || isIPad) ? 100 : 74,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = player.duration ?? Duration.zero;
                    final progress = duration.inMilliseconds > 0
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0.0;
                    return LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary),
                    );
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'now_playing_art_${metadata.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: GruImage(
                              key: ValueKey('art_${metadata.id}'),
                              url: metadata.artUri?.toString() ?? '',
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorWidget: const Icon(Icons.music_note),
                            ),
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                metadata.artist ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12),
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
                                final isFavorite =
                                    userData.favorites.contains(metadata.id);
                                final isSuggestLess =
                                    userData.suggestLess.contains(metadata.id);

                                return GestureDetector(
                                  onLongPress: () {
                                    final songs =
                                        ref.read(songsProvider).value ?? [];
                                    final song = songs
                                        .where((s) => s.filename == metadata.id)
                                        .firstOrNull;
                                    showSongOptionsMenu(context, ref,
                                        metadata.id, metadata.title,
                                        song: song);
                                  },
                                  child: IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    icon: Icon(
                                      isSuggestLess
                                          ? Icons.heart_broken
                                          : (isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border),
                                      size: 22,
                                    ),
                                    color: isSuggestLess
                                        ? Colors.grey
                                        : (isFavorite ? Colors.red : null),
                                    onPressed: () {
                                      ref
                                          .read(userDataProvider.notifier)
                                          .toggleFavorite(metadata.id);
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
                                final processingState =
                                    playerState?.processingState;

                                if (processingState ==
                                    ProcessingState.buffering) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  );
                                }

                                return IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  icon: Icon(
                                      playing ? Icons.pause : Icons.play_arrow,
                                      size: 28),
                                  onPressed:
                                      playing ? player.pause : player.play,
                                );
                              },
                            ),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                              icon: const Icon(Icons.skip_next, size: 24),
                              onPressed:
                                  player.hasNext ? player.seekToNext : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

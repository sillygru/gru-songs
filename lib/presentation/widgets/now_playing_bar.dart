import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'album_art_image.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../screens/player_screen.dart';
import 'audio_visualizer.dart';

class NowPlayingBar extends ConsumerStatefulWidget {
  const NowPlayingBar({super.key});

  @override
  ConsumerState<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends ConsumerState<NowPlayingBar> {
  String? _lastSongId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = ref.watch(audioPlayerManagerProvider).player;
    final settings = ref.watch(settingsProvider);
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

        if (metadata.id != _lastSongId) {
          _lastSongId = metadata.id;
        }

        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const PlayerScreen(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  height: (isDesktop || isIPad) ? 90 : 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'now_playing_art_${metadata.id}',
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      AlbumArtImage(
                                        key: ValueKey(
                                            'now_playing_art_${metadata.id}'),
                                        url: metadata.artUri?.toString() ?? '',
                                        filename: metadata.id,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                      StreamBuilder<PlayerState>(
                                        stream: player.playerStateStream,
                                        builder: (context, snapshot) {
                                          final playing =
                                              snapshot.data?.playing ?? false;
                                          if (!playing) {
                                            return const SizedBox.shrink();
                                          }

                                          return Positioned.fill(
                                            child: Container(
                                              color: Colors.black
                                                  .withValues(alpha: 0.3),
                                              child: Center(
                                                child:
                                                    settings.visualizerEnabled
                                                        ? const AudioVisualizer(
                                                            width: 24,
                                                            height: 24,
                                                            color: Colors.white,
                                                            isPlaying: true,
                                                          )
                                                        : const Icon(
                                                            Icons.graphic_eq,
                                                            color: Colors.white,
                                                            size: 20),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
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
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: -0.5),
                                  ),
                                  Text(
                                    metadata.artist ?? 'Unknown Artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.6),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isDesktop || isIPad) ...[
                              const Icon(Icons.volume_down,
                                  size: 18, color: Colors.white60),
                              SizedBox(
                                width: 100,
                                child: StreamBuilder<double>(
                                  stream: player.volumeStream,
                                  builder: (context, snapshot) {
                                    return Slider(
                                      value: snapshot.data ?? 1.0,
                                      activeColor: theme.colorScheme.primary,
                                      onChanged: player.setVolume,
                                    );
                                  },
                                ),
                              ),
                              const Icon(Icons.volume_up,
                                  size: 18, color: Colors.white60),
                              const SizedBox(width: 12),
                            ],
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StreamBuilder<PlayerState>(
                                  stream: player.playerStateStream,
                                  builder: (context, snapshot) {
                                    final playerState = snapshot.data;
                                    final playing =
                                        playerState?.playing ?? false;
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
                                                strokeWidth: 2,
                                                color: Colors.white)),
                                      );
                                    }

                                    return IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(8),
                                      icon: Icon(
                                          playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 34,
                                          color: Colors.white),
                                      onPressed:
                                          playing ? player.pause : player.play,
                                    );
                                  },
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(Icons.skip_next_rounded,
                                      size: 30, color: Colors.white),
                                  onPressed:
                                      player.hasNext ? player.seekToNext : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            final duration = player.duration ?? Duration.zero;
                            final progress = duration.inMilliseconds > 0
                                ? position.inMilliseconds /
                                    duration.inMilliseconds
                                : 0.0;
                            return LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

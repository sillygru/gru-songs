import 'dart:io';
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
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Container(
              height: (isDesktop || isIPad) ? 90 : 66,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'now_playing_art_${metadata.id}',
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    children: [
                                      AlbumArtImage(
                                        key: ValueKey(
                                            'now_playing_art_${metadata.id}'),
                                        url: metadata.artUri?.toString() ?? '',
                                        filename: metadata.id,
                                        width: 44,
                                        height: 44,
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
                                                            width: 20,
                                                            height: 20,
                                                            color: Colors.white,
                                                            isPlaying: true,
                                                          )
                                                        : const Icon(
                                                            Icons.graphic_eq,
                                                            color: Colors.white,
                                                            size: 18),
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
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: -0.2),
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
                              const Icon(Icons.volume_down, size: 18),
                              SizedBox(
                                width: 100,
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
                              const Icon(Icons.volume_up, size: 18),
                              const SizedBox(width: 8),
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
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      );
                                    }

                                    return IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(8),
                                      icon: Icon(
                                          playing
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          size: 30),
                                      onPressed:
                                          playing ? player.pause : player.play,
                                    );
                                  },
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  icon: const Icon(Icons.skip_next, size: 26),
                                  onPressed:
                                      player.hasNext ? player.seekToNext : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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
                          minHeight: 2.5,
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

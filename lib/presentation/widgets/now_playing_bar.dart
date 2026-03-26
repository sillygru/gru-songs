import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'album_art_image.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../routes/player_route.dart';
import 'audio_visualizer.dart';

class NowPlayingBar extends ConsumerStatefulWidget {
  final EdgeInsetsGeometry padding;
  final bool embedded;
  final bool compact;

  const NowPlayingBar({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 12),
    this.embedded = false,
    this.compact = false,
  });

  @override
  ConsumerState<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends ConsumerState<NowPlayingBar> {
  String? _lastSongId;

  void _openPlayer(BuildContext context, MediaItem metadata) {
    Navigator.of(context).push(PlayerPageRoute(songId: metadata.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = ref.watch(audioPlayerManagerProvider).player;
    final settings = ref.watch(settingsProvider);
    final isBarVisible =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
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
          onTap: () => _openPlayer(context, metadata),
          child: Padding(
            padding: widget.padding,
            child: _NowPlayingContent(
              metadata: metadata,
              player: player,
              settingsEnabled: settings.visualizerEnabled,
              isBarVisible: isBarVisible,
              theme: theme,
              isDesktopOrTablet: isDesktop || isIPad,
              compact: widget.compact,
              embedded: widget.embedded,
            ),
          ),
        );
      },
    );
  }
}

class _NowPlayingContent extends ConsumerWidget {
  final MediaItem metadata;
  final AudioPlayer player;
  final bool settingsEnabled;
  final bool isBarVisible;
  final ThemeData theme;
  final bool isDesktopOrTablet;
  final bool compact;
  final bool embedded;

  const _NowPlayingContent({
    required this.metadata,
    required this.player,
    required this.settingsEnabled,
    required this.isBarVisible,
    required this.theme,
    required this.isDesktopOrTablet,
    required this.compact,
    required this.embedded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double barHeight =
        compact ? (isDesktopOrTablet ? 72 : 60) : (isDesktopOrTablet ? 78 : 64);
    final double imageSize = compact ? 40 : 44;
    final double titleSize = compact ? 14 : 15;
    final double artistSize = compact ? 11 : 12;
    final BorderRadius borderRadius = BorderRadius.circular(compact ? 20 : 22);

    final Widget content = SizedBox(
      height: barHeight,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
            child: Row(
              children: [
                Hero(
                  tag: 'now_playing_art_${metadata.id}',
                  child: Container(
                    width: imageSize,
                    height: imageSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          AlbumArtImage(
                            key: ValueKey('now_playing_art_${metadata.id}'),
                            url: metadata.artUri?.toString() ?? '',
                            filename: metadata.id,
                            width: imageSize,
                            height: imageSize,
                            fit: BoxFit.cover,
                          ),
                          StreamBuilder<PlayerState>(
                            stream: player.playerStateStream,
                            builder: (context, snapshot) {
                              final playing = snapshot.data?.playing ?? false;
                              if (!playing || !isBarVisible) {
                                return const SizedBox.shrink();
                              }

                              return Positioned.fill(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  child: Center(
                                    child: settingsEnabled
                                        ? AudioVisualizer(
                                            width: compact ? 18 : 22,
                                            height: compact ? 18 : 22,
                                            color: Colors.white,
                                            isPlaying: true,
                                          )
                                        : Icon(
                                            Icons.graphic_eq,
                                            color: Colors.white,
                                            size: compact ? 17 : 19,
                                          ),
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
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: titleSize,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        metadata.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontWeight: FontWeight.w500,
                          fontSize: artistSize,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!compact && isDesktopOrTablet) ...[
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
                  const Icon(Icons.volume_up, size: 18, color: Colors.white60),
                  const SizedBox(width: 12),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        final playing = playerState?.playing ?? false;
                        final processingState = playerState?.processingState;

                        if (processingState == ProcessingState.buffering) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }

                        return IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                          icon: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: compact ? 28 : 30,
                            color: Colors.white,
                          ),
                          onPressed: () => ref
                              .read(audioPlayerManagerProvider)
                              .togglePlayPause(),
                        );
                      },
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                      icon: Icon(
                        Icons.skip_next_rounded,
                        size: compact ? 24 : 28,
                        color: Colors.white,
                      ),
                      onPressed: player.hasNext ? player.seekToNext : null,
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
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0.0;
                return LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: compact ? 2.5 : 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (embedded) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

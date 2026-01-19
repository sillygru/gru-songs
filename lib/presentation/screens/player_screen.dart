import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../widgets/gru_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/song_options_menu.dart';
import '../widgets/next_up_sheet.dart';

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showLyrics = false;
  List<LyricLine>? _lyrics;
  List<GlobalKey>? _lyricKeys;
  bool _loadingLyrics = false;
  bool _autoScrollEnabled = true;
  String? _lastSongId;
  final ScrollController _lyricsScrollController = ScrollController();
  final GlobalKey _lyricsContainerKey = GlobalKey();
  int _currentLyricIndex = -1;

  AudioPlayer get player => ref.read(audioPlayerManagerProvider).player;

  @override
  void initState() {
    super.initState();
    player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      final String? songId = tag is MediaItem ? tag.id : null;

      if (songId != _lastSongId) {
        if (mounted) {
          setState(() {
            _lastSongId = songId;
            _lyrics = null;
            _lyricKeys = null;
            _showLyrics = false;
            _loadingLyrics = false;
            _autoScrollEnabled = true;
            _currentLyricIndex = -1;
          });
        }
      }
    });

    player.positionStream.listen((position) {
      if (_lyrics != null && _lyrics!.any((l) => l.time != Duration.zero)) {
        int newIndex = -1;
        for (int i = 0; i < _lyrics!.length; i++) {
          if (_lyrics![i].time <= position &&
              _lyrics![i].time != Duration.zero) {
            newIndex = i;
          } else if (_lyrics![i].time > position) {
            break;
          }
        }

        if (newIndex != _currentLyricIndex && newIndex != -1) {
          if (mounted) {
            setState(() {
              _currentLyricIndex = newIndex;
            });
            if (_showLyrics && _autoScrollEnabled) {
              _scrollToCurrentLyric();
            }
          }
        }
      }
    });
  }

  void _updateCurrentLyricIndex(Duration position) {
    if (_lyrics == null || _lyrics!.isEmpty) return;

    int newIndex = -1;
    for (int i = 0; i < _lyrics!.length; i++) {
      if (_lyrics![i].time <= position && _lyrics![i].time != Duration.zero) {
        newIndex = i;
      } else if (_lyrics![i].time > position) {
        break;
      }
    }

    if (newIndex != -1 && newIndex != _currentLyricIndex) {
      setState(() => _currentLyricIndex = newIndex);
    }
  }

  void _checkAndReenableAutoScroll() {
    if (_currentLyricIndex == -1 || _lyricKeys == null || !_showLyrics) return;

    final key = _lyricKeys![_currentLyricIndex];
    final context = key.currentContext;
    final containerContext = _lyricsContainerKey.currentContext;

    if (context != null && containerContext != null) {
      final RenderBox box = context.findRenderObject() as RenderBox;
      final RenderBox containerBox =
          containerContext.findRenderObject() as RenderBox;

      final lyricOffset =
          box.localToGlobal(Offset.zero, ancestor: containerBox).dy;
      final viewportHeight = containerBox.size.height;
      final lyricCenter = lyricOffset + box.size.height / 2;
      final viewportCenter = viewportHeight / 2;

      // If current lyric center is within 150px of viewport center, re-enable sync
      if ((lyricCenter - viewportCenter).abs() < 150) {
        if (mounted && !_autoScrollEnabled) {
          setState(() => _autoScrollEnabled = true);
          _scrollToCurrentLyric();
        }
      }
    }
  }

  void _scrollToCurrentLyric() {
    if (_lyricKeys != null &&
        _currentLyricIndex >= 0 &&
        _currentLyricIndex < _lyricKeys!.length) {
      final key = _lyricKeys![_currentLyricIndex];
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    }
  }

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _toggleLyrics(String? lyricsUrl) async {
    if (_showLyrics) {
      setState(() => _showLyrics = false);
      return;
    }

    if (lyricsUrl == null) return;

    setState(() {
      _showLyrics = true;
      _autoScrollEnabled = true;
      if (_lyrics == null) _loadingLyrics = true;
    });

    if (_lyrics == null) {
      final repo = ref.read(songRepositoryProvider);
      final lyricsContent = await repo.getLyrics(lyricsUrl);
      if (mounted) {
        final parsedLyrics = lyricsContent != null
            ? LyricLine.parse(lyricsContent)
            : <LyricLine>[];
        setState(() {
          _lyrics = parsedLyrics;
          _lyricKeys =
              List.generate(parsedLyrics.length, (index) => GlobalKey());
          _loadingLyrics = false;
        });

        // Find current position and scroll after first build
        _updateCurrentLyricIndex(player.position);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showLyrics) _scrollToCurrentLyric();
        });
      }
    } else {
      // Already loaded, just scroll to current
      _updateCurrentLyricIndex(player.position);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showLyrics) _scrollToCurrentLyric();
      });
    }
  }

  void _showShuffleSettings(BuildContext context, WidgetRef ref) {
    final manager = ref.read(audioPlayerManagerProvider);

    showDialog(
      context: context,
      builder: (context) {
        return ValueListenableBuilder(
          valueListenable: manager.shuffleStateNotifier,
          builder: (context, state, child) {
            final config = state.config;
            return AlertDialog(
              title: const Text('Shuffle Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Anti-repeat'),
                    subtitle:
                        const Text('Reduce probability for recently played'),
                    value: config.antiRepeatEnabled,
                    onChanged: (val) {
                      manager.updateShuffleConfig(
                          config.copyWith(antiRepeatEnabled: val));
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Streak Breaker'),
                    subtitle: const Text('Avoid same artist/album in a row'),
                    value: config.streakBreakerEnabled,
                    onChanged: (val) {
                      manager.updateShuffleConfig(
                          config.copyWith(streakBreakerEnabled: val));
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Favorite Boost'),
                    subtitle: Text(
                        '${((config.favoriteMultiplier - 1) * 100).round()}% higher weight'),
                  ),
                  ListTile(
                    title: const Text('Suggest-Less Penalty'),
                    subtitle: Text(
                        '${((1 - config.suggestLessMultiplier) * 100).round()}% lower weight'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          player.positionStream,
          player.bufferedPositionStream,
          player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final isIPad = !kIsWeb &&
        Platform.isIOS &&
        MediaQuery.of(context).size.shortestSide >= 600;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: StreamBuilder<SequenceState?>(
        stream: player.sequenceStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final metadata = state?.currentSource?.tag as MediaItem?;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2)),
              ),
              if (metadata != null) ...[
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    return GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.primaryDelta! < -5) {
                          if (!_showLyrics &&
                              metadata.extras?['lyricsUrl'] != null) {
                            _toggleLyrics(
                                metadata.extras!['lyricsUrl'] as String);
                          }
                        } else if (details.primaryDelta! > 5) {
                          if (_showLyrics) {
                            setState(() => _showLyrics = false);
                          }
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: !_showLyrics
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Hero(
                                    tag: 'now_playing_art_${metadata.id}',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.4),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: GruImage(
                                          key: ValueKey('art_${metadata.id}'),
                                          url: metadata.artUri?.toString() ?? '',
                                          width: constraints.maxWidth,
                                          height: constraints.maxWidth,
                                          cacheWidth:
                                              600, // Reasonable cap for RAM
                                          fit: BoxFit.cover,
                                          errorWidget: const Icon(
                                              Icons.music_note,
                                              size: 100),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Stack(
                                  children: [
                                    // Immersive Blurred Background
                                    Positioned.fill(
                                      child: Hero(
                                        tag: 'lyrics_bg_${metadata.id}',
                                        child: GruImage(
                                          url: metadata.artUri?.toString() ?? '',
                                          fit: BoxFit.cover,
                                          cacheWidth: 600,
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 50, sigmaY: 50),
                                        child: Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ),
                                    // Gradient overlay for better readability and fade effects
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.black
                                                  .withValues(alpha: 0.3),
                                              Colors.transparent,
                                              Colors.transparent,
                                              Colors.black
                                                  .withValues(alpha: 0.3),
                                            ],
                                            stops: const [0.0, 0.2, 0.8, 1.0],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      key: _lyricsContainerKey,
                                      child: _loadingLyrics
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator())
                                          : (_lyrics == null ||
                                                  _lyrics!.isEmpty)
                                              ? const Center(
                                                  child: Text(
                                                    'No lyrics available',
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 18),
                                                  ),
                                                )
                                              : ShaderMask(
                                                  shaderCallback: (rect) {
                                                    return const LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        Colors.black,
                                                        Colors.transparent,
                                                        Colors.transparent,
                                                        Colors.black
                                                      ],
                                                      stops: [
                                                        0.0,
                                                        0.05,
                                                        0.95,
                                                        1.0
                                                      ],
                                                    ).createShader(rect);
                                                  },
                                                  blendMode: BlendMode.dstOut,
                                                  child: NotificationListener<
                                                      ScrollNotification>(
                                                    onNotification:
                                                        (notification) {
                                                      if (notification
                                                          is UserScrollNotification) {
                                                        if (notification
                                                                .direction !=
                                                            ScrollDirection
                                                                .idle) {
                                                          if (_autoScrollEnabled) {
                                                            setState(() =>
                                                                _autoScrollEnabled =
                                                                    false);
                                                          }
                                                        }
                                                      } else if (notification
                                                          is ScrollEndNotification) {
                                                        _checkAndReenableAutoScroll();
                                                      }
                                                      return false;
                                                    },
                                                    child:
                                                        SingleChildScrollView(
                                                      controller:
                                                          _lyricsScrollController,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 80),
                                                      child: Column(
                                                        children: List.generate(
                                                            _lyrics!.length,
                                                            (index) {
                                                          final isCurrent = index ==
                                                              _currentLyricIndex;
                                                          final hasTime =
                                                              _lyrics![index]
                                                                      .time !=
                                                                  Duration.zero;
                                                          return InkWell(
                                                            key: _lyricKeys?[
                                                                index],
                                                            onTap: hasTime
                                                                ? () {
                                                                    player.seek(
                                                                        _lyrics![index]
                                                                            .time);
                                                                    setState(() =>
                                                                        _autoScrollEnabled =
                                                                            true);
                                                                  }
                                                                : null,
                                                            child:
                                                                AnimatedContainer(
                                                              duration:
                                                                  const Duration(
                                                                      milliseconds:
                                                                          500),
                                                              curve: Curves
                                                                  .easeOutQuart,
                                                              width: double
                                                                  .infinity,
                                                              padding: EdgeInsets
                                                                  .symmetric(
                                                                      horizontal:
                                                                          24,
                                                                      vertical: isCurrent
                                                                          ? 28
                                                                          : 16),
                                                              child:
                                                                  AnimatedDefaultTextStyle(
                                                                duration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            500),
                                                                curve: Curves
                                                                    .easeOutQuart,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      isCurrent
                                                                          ? 32
                                                                          : 24,
                                                                  fontWeight: isCurrent
                                                                      ? FontWeight
                                                                          .bold
                                                                      : FontWeight
                                                                          .w600,
                                                                  color: isCurrent
                                                                      ? Colors
                                                                          .white
                                                                      : Colors
                                                                          .white
                                                                          .withValues(
                                                                              alpha: 0.35),
                                                                  height: 1.3,
                                                                  letterSpacing:
                                                                      isCurrent
                                                                          ? -0.8
                                                                          : -0.2,
                                                                  shadows:
                                                                      isCurrent
                                                                          ? [
                                                                              Shadow(
                                                                                color: Colors.black.withValues(alpha: 0.3),
                                                                                offset: const Offset(0, 4),
                                                                                blurRadius: 12,
                                                                              )
                                                                            ]
                                                                          : [],
                                                                ),
                                                                child: Text(
                                                                    _lyrics![
                                                                            index]
                                                                        .text),
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Text(
                  metadata.title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${metadata.artist ?? 'Unknown Artist'} • ${metadata.album ?? 'Unknown Album'}',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 32),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return ProgressBar(
                    progress: positionData?.position ?? Duration.zero,
                    buffered: positionData?.bufferedPosition ?? Duration.zero,
                    total: positionData?.duration ?? Duration.zero,
                    onSeek: player.seek,
                  );
                },
              ),
              if (isDesktop || isIPad) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.volume_down, size: 20),
                    Expanded(
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
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Lyrics
                  IconButton(
                    icon: const Icon(Icons.lyrics_outlined),
                    color: _showLyrics ? Colors.deepPurple : Colors.white70,
                    onPressed: () {
                      if (metadata?.extras?['lyricsUrl'] != null) {
                        _toggleLyrics(metadata!.extras!['lyricsUrl'] as String);
                      }
                    },
                  ),
                  // Queue
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    color: Colors.white70,
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const NextUpSheet(),
                      );
                    },
                  ),
                  // Shuffle
                  ValueListenableBuilder<bool>(
                    valueListenable:
                        ref.read(audioPlayerManagerProvider).shuffleNotifier,
                    builder: (context, isShuffled, child) {
                      return IconButton(
                        icon: Icon(Icons.shuffle,
                            color: isShuffled
                                ? Colors.deepPurple
                                : Colors.white70),
                        onLongPress: () => _showShuffleSettings(context, ref),
                        onPressed: () async {
                          await ref
                              .read(audioPlayerManagerProvider)
                              .toggleShuffle();
                        },
                      );
                    },
                  ),
                  // Repeat
                  StreamBuilder<LoopMode>(
                    stream: player.loopModeStream,
                    builder: (context, snapshot) {
                      final loopMode = snapshot.data ?? LoopMode.off;
                      IconData iconData = Icons.repeat;
                      Color color = Colors.white70;
                      if (loopMode == LoopMode.one) {
                        iconData = Icons.repeat_one;
                        color = Colors.deepPurple;
                      } else if (loopMode == LoopMode.all) {
                        iconData = Icons.repeat;
                        color = Colors.deepPurple;
                      }
                      return IconButton(
                        icon: Icon(iconData, color: color),
                        onPressed: () {
                          final nextMode = LoopMode.values[
                              (loopMode.index + 1) % LoopMode.values.length];
                          player.setLoopMode(nextMode);
                        },
                      );
                    },
                  ),
                  // Favorite
                  GestureDetector(
                    onLongPress: () {
                      if (metadata != null) {
                        final songs = ref.read(songsProvider).value ?? [];
                        final song = songs
                            .where((s) => s.filename == metadata.id)
                            .firstOrNull;
                        showSongOptionsMenu(
                            context, ref, metadata.id, metadata.title,
                            song: song);
                      }
                    },
                    child: IconButton(
                      icon: Icon(userData.isFavorite(metadata?.id ?? '')
                          ? Icons.favorite
                          : Icons.favorite_border),
                      color: userData.isFavorite(metadata?.id ?? '')
                          ? Colors.red
                          : Colors.white70,
                      onPressed: () {
                        if (metadata != null) {
                          ref
                              .read(userDataProvider.notifier)
                              .toggleFavorite(metadata.id);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 48),
                    onPressed: () {
                      if (player.position.inSeconds > 3) {
                        player.seek(Duration.zero);
                      } else {
                        player.seekToPrevious();
                      }
                    },
                  ),
                  const SizedBox(width: 24),
                  // Play/Pause
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? false;
                      return IconButton(
                        icon: Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            size: 84),
                        onPressed: playing ? player.pause : player.play,
                      );
                    },
                  ),
                  const SizedBox(width: 24),
                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 48),
                    onPressed: player.hasNext ? player.seekToNext : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../widgets/album_art_image.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/heart_context_menu.dart';
import '../widgets/next_up_sheet.dart';
import '../widgets/waveform_progress_bar.dart';
import 'song_list_screen.dart';

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

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  bool _showLyrics = false;
  List<LyricLine>? _lyrics;
  List<GlobalKey>? _lyricKeys;
  bool _loadingLyrics = false;
  bool _autoScrollEnabled = true;
  String? _lastSongId;
  final ScrollController _lyricsScrollController = ScrollController();
  final GlobalKey _lyricsContainerKey = GlobalKey();
  final ValueNotifier<int> _currentLyricIndexNotifier = ValueNotifier<int>(-1);
  late TapGestureRecognizer _artistRecognizer;
  late TapGestureRecognizer _albumRecognizer;
  late AnimationController _playPauseController;

  AudioPlayer get player => ref.read(audioPlayerManagerProvider).player;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _artistRecognizer = TapGestureRecognizer();
    _albumRecognizer = TapGestureRecognizer();
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
            _currentLyricIndexNotifier.value = -1;
          });
        }
      }
    });

    // Sync animation controller with player state
    player.playerStateStream.listen((state) {
      if (state.playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
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

        if (newIndex != _currentLyricIndexNotifier.value && newIndex != -1) {
          _currentLyricIndexNotifier.value = newIndex;
          if (_showLyrics && _autoScrollEnabled) {
            _scrollToCurrentLyric();
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

    if (newIndex != -1 && newIndex != _currentLyricIndexNotifier.value) {
      _currentLyricIndexNotifier.value = newIndex;
    }
  }

  void _checkAndReenableAutoScroll() {
    if (_currentLyricIndexNotifier.value == -1 ||
        _lyricKeys == null ||
        !_showLyrics) {
      return;
    }

    final key = _lyricKeys![_currentLyricIndexNotifier.value];
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
        _currentLyricIndexNotifier.value >= 0 &&
        _currentLyricIndexNotifier.value < _lyricKeys!.length) {
      final key = _lyricKeys![_currentLyricIndexNotifier.value];
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
    _currentLyricIndexNotifier.dispose();
    _playPauseController.dispose();
    _lyricsScrollController.dispose();
    _artistRecognizer.dispose();
    _albumRecognizer.dispose();
    super.dispose();
  }

  void _toggleLyrics() async {
    if (_showLyrics) {
      setState(() => _showLyrics = false);
      return;
    }

    setState(() {
      _showLyrics = true;
      _autoScrollEnabled = true;
      if (_lyrics == null) _loadingLyrics = true;
    });

    if (_lyrics == null) {
      // Get current song from player
      final sequenceState = player.sequenceState;
      final currentSource = sequenceState?.currentSource;
      final tag = currentSource?.tag;
      if (tag is MediaItem) {
        final songs = ref.read(songsProvider).asData?.value ?? [];
        final currentSong = songs.cast<Song?>().firstWhere(
              (s) => s?.filename == tag.id,
              orElse: () => null,
            );
        if (currentSong != null) {
          final repo = ref.read(songRepositoryProvider);
          final lyricsContent = await repo.getLyrics(currentSong);
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
          if (mounted) setState(() => _loadingLyrics = false);
        }
      } else {
        if (mounted) setState(() => _loadingLyrics = false);
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

  void _navigateToArtist(String artist) {
    final allSongs = ref.read(songsProvider).value ?? [];
    final artistSongs = allSongs.where((s) {
      final songArtist = s.artist.isEmpty ? 'Unknown Artist' : s.artist;
      return songArtist == artist;
    }).toList();

    if (artistSongs.isNotEmpty) {
      // Close player screen first
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SongListScreen(
            title: artist,
            songs: artistSongs,
          ),
        ),
      );
    }
  }

  void _navigateToAlbum(String album) {
    final allSongs = ref.read(songsProvider).value ?? [];
    final albumSongs = allSongs.where((s) {
      final songAlbum = s.album.isEmpty ? 'Unknown Album' : s.album;
      return songAlbum == album;
    }).toList();

    if (albumSongs.isNotEmpty) {
      // Close player screen first
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SongListScreen(
            title: album,
            songs: albumSongs,
          ),
        ),
      );
    }
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
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final isIPad = !kIsWeb &&
        Platform.isIOS &&
        MediaQuery.of(context).size.shortestSide >= 600;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final metadata = state?.currentSource?.tag as MediaItem?;

            return Stack(
              children: [
                // Immersive Background for the whole screen
                if (metadata != null) ...[
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Opacity(
                        opacity: 0.2,
                        child: AlbumArtImage(
                          url: metadata.artUri?.toString() ?? '',
                          filename: metadata.id,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.8),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 32),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      if (metadata != null) ...[
                        Expanded(
                          child: RepaintBoundary(
                            child:
                                LayoutBuilder(builder: (context, constraints) {
                              return GestureDetector(
                                onVerticalDragUpdate: (details) {
                                  if (details.primaryDelta! < -5) {
                                    if (!_showLyrics) {
                                      _toggleLyrics();
                                    }
                                  } else if (details.primaryDelta! > 5) {
                                    if (_showLyrics) {
                                      setState(() => _showLyrics = false);
                                    }
                                  }
                                },
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                  },
                                  child: !_showLyrics
                                      ? Center(
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                                    begin: 0.92, end: 1.0)
                                                .animate(CurvedAnimation(
                                              parent: _playPauseController,
                                              curve: Curves.easeOutBack,
                                            )),
                                            child: AspectRatio(
                                              aspectRatio: 1,
                                              child: Hero(
                                                tag:
                                                    'now_playing_art_${metadata.id}',
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    // Main Image
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(28),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withValues(
                                                                    alpha: 0.4),
                                                            blurRadius: 25,
                                                            offset:
                                                                const Offset(
                                                                    0, 10),
                                                          ),
                                                        ],
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(28),
                                                        child: AlbumArtImage(
                                                          key: ValueKey(
                                                              'art_${metadata.id}'),
                                                          url: metadata.artUri
                                                                  ?.toString() ??
                                                              '',
                                                          filename: metadata.id,
                                                          width: constraints
                                                              .maxWidth,
                                                          height: constraints
                                                              .maxWidth,
                                                          cacheWidth: 800,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          child: Stack(
                                            children: [
                                              // Background for lyrics
                                              Positioned.fill(
                                                child: Opacity(
                                                  opacity: 0.15,
                                                  child: AlbumArtImage(
                                                    url: metadata.artUri
                                                            ?.toString() ??
                                                        '',
                                                    filename: metadata.id,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 400,
                                                  ),
                                                ),
                                              ),
                                              Positioned.fill(
                                                child: Container(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              _loadingLyrics
                                                  ? const Center(
                                                      child:
                                                          CircularProgressIndicator())
                                                  : (_lyrics == null ||
                                                          _lyrics!.isEmpty)
                                                      ? const Center(
                                                          child: Text(
                                                            'No lyrics available',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white70,
                                                                fontSize: 18),
                                                          ),
                                                        )
                                                      : NotificationListener<
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
                                                              ValueListenableBuilder<
                                                                  int>(
                                                            valueListenable:
                                                                _currentLyricIndexNotifier,
                                                            builder: (context,
                                                                currentIndex,
                                                                child) {
                                                              return ListView
                                                                  .builder(
                                                                key:
                                                                    _lyricsContainerKey,
                                                                controller:
                                                                    _lyricsScrollController,
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        120),
                                                                itemCount:
                                                                    _lyrics!
                                                                        .length,
                                                                itemBuilder:
                                                                    (context,
                                                                        index) {
                                                                  final isCurrent =
                                                                      index ==
                                                                          currentIndex;
                                                                  final hasTime = _lyrics![
                                                                              index]
                                                                          .time !=
                                                                      Duration
                                                                          .zero;
                                                                  return InkWell(
                                                                    key: _lyricKeys?[
                                                                        index],
                                                                    onTap: hasTime
                                                                        ? () {
                                                                            player.seek(_lyrics![index].time);
                                                                            setState(() =>
                                                                                _autoScrollEnabled = true);
                                                                          }
                                                                        : null,
                                                                    child:
                                                                        Padding(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          horizontal:
                                                                              24,
                                                                          vertical:
                                                                              12),
                                                                      child:
                                                                          Text(
                                                                        _lyrics![index]
                                                                            .text,
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style:
                                                                            TextStyle(
                                                                          fontSize:
                                                                              26,
                                                                          fontWeight: isCurrent
                                                                              ? FontWeight.bold
                                                                              : FontWeight.w500,
                                                                          color: isCurrent
                                                                              ? Colors.white
                                                                              : Colors.white.withValues(alpha: 0.3),
                                                                          height:
                                                                              1.3,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                            ],
                                          ),
                                        ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          metadata.title,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamily,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            children: [
                              TextSpan(
                                text: metadata.artist ?? 'Unknown Artist',
                                recognizer: _artistRecognizer
                                  ..onTap = () => _navigateToArtist(
                                      metadata.artist ?? 'Unknown Artist'),
                              ),
                              const TextSpan(text: ' • '),
                              TextSpan(
                                text: metadata.album ?? 'Unknown Album',
                                recognizer: _albumRecognizer
                                  ..onTap = () => _navigateToAlbum(
                                      metadata.album ?? 'Unknown Album'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      RepaintBoundary(
                        child: StreamBuilder<PositionData>(
                          stream: _positionDataStream,
                          builder: (context, snapshot) {
                            if (metadata == null) {
                              return const SizedBox.shrink();
                            }
                            final positionData = snapshot.data;
                            return WaveformProgressBar(
                              filename: metadata.id,
                              path: metadata.extras?['audioPath'] ?? '',
                              progress: positionData?.position ?? Duration.zero,
                              total: positionData?.duration ?? Duration.zero,
                              onSeek: player.seek,
                            );
                          },
                        ),
                      ),
                      if (isDesktop || isIPad) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.volume_down,
                                size: 20, color: Colors.white60),
                            Expanded(
                              child: StreamBuilder<double>(
                                stream: player.volumeStream,
                                builder: (context, snapshot) {
                                  return Slider(
                                    value: snapshot.data ?? 1.0,
                                    activeColor:
                                        Theme.of(context).colorScheme.primary,
                                    inactiveColor: Colors.white10,
                                    onChanged: player.setVolume,
                                  );
                                },
                              ),
                            ),
                            const Icon(Icons.volume_up,
                                size: 20, color: Colors.white60),
                          ],
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Secondary Controls
                      RepaintBoundary(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Lyrics
                            IconButton(
                              icon: const Icon(Icons.lyrics_outlined),
                              color: _showLyrics
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white60,
                              onPressed: () {
                                _toggleLyrics();
                              },
                            ),
                            const SizedBox(width: 32),
                            // Queue
                            IconButton(
                              icon: const Icon(Icons.queue_music),
                              color: Colors.white60,
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => const NextUpSheet(),
                                );
                              },
                            ),
                            const SizedBox(width: 32),
                            // Favorite
                            if (metadata != null)
                              Consumer(
                                builder: (context, ref, child) {
                                  final isFav = ref.watch(
                                      userDataProvider.select(
                                          (s) => s.isFavorite(metadata.id)));
                                  return GestureDetector(
                                    onLongPress: () {
                                      showHeartContextMenu(
                                        context: context,
                                        ref: ref,
                                        songFilename: metadata.id,
                                        songTitle: metadata.title,
                                      );
                                    },
                                    child: IconButton(
                                      icon: Icon(isFav
                                          ? Icons.favorite
                                          : Icons.favorite_border),
                                      color: isFav
                                          ? Colors.redAccent
                                          : Colors.white60,
                                      onPressed: () {
                                        ref
                                            .read(userDataProvider.notifier)
                                            .toggleFavorite(metadata.id);
                                      },
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Main Controls
                      RepaintBoundary(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Repeat
                            StreamBuilder<LoopMode>(
                              stream: player.loopModeStream,
                              builder: (context, snapshot) {
                                final loopMode = snapshot.data ?? LoopMode.off;
                                IconData iconData = Icons.repeat;
                                Color color = Colors.white60;
                                if (loopMode == LoopMode.one) {
                                  iconData = Icons.repeat_one;
                                  color = Theme.of(context).colorScheme.primary;
                                } else if (loopMode == LoopMode.all) {
                                  iconData = Icons.repeat;
                                  color = Theme.of(context).colorScheme.primary;
                                }
                                return IconButton(
                                  icon: Icon(iconData, color: color, size: 24),
                                  onPressed: () {
                                    final nextMode = LoopMode.values[
                                        (loopMode.index + 1) %
                                            LoopMode.values.length];
                                    player.setLoopMode(nextMode);
                                  },
                                );
                              },
                            ),

                            // Control Cluster (Rewind, Play, Next)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Previous
                                Container(
                                  height: 55,
                                  width: 55,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                        Icons.skip_previous_rounded,
                                        size: 26),
                                    color: Colors.white,
                                    onPressed: () {
                                      if (player.position.inSeconds > 3) {
                                        player.seek(Duration.zero);
                                      } else {
                                        player.seekToPrevious();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Play/Pause
                                StreamBuilder<PlayerState>(
                                  stream: player.playerStateStream,
                                  builder: (context, snapshot) {
                                    final playerState = snapshot.data;
                                    final playing =
                                        playerState?.playing ?? false;
                                    return Container(
                                      height: 75,
                                      width: 100,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.3),
                                            blurRadius: 15,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: AnimatedIcon(
                                          icon: AnimatedIcons.play_pause,
                                          progress: _playPauseController,
                                          size: 42,
                                          color: Colors.white,
                                        ),
                                        onPressed: playing
                                            ? player.pause
                                            : player.play,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                // Next
                                Container(
                                  height: 55,
                                  width: 55,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.skip_next_rounded,
                                        size: 26),
                                    color: Colors.white,
                                    onPressed: player.hasNext
                                        ? player.seekToNext
                                        : null,
                                  ),
                                ),
                              ],
                            ),

                            // Shuffle
                            ValueListenableBuilder<bool>(
                              valueListenable: ref
                                  .read(audioPlayerManagerProvider)
                                  .shuffleNotifier,
                              builder: (context, isShuffled, child) {
                                return IconButton(
                                  icon: Icon(Icons.shuffle,
                                      size: 24,
                                      color: isShuffled
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.white60),
                                  onLongPress: () =>
                                      _showShuffleSettings(context, ref),
                                  onPressed: () async {
                                    await ref
                                        .read(audioPlayerManagerProvider)
                                        .toggleShuffle();
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/album_art_image.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/heart_context_menu.dart';
import '../widgets/next_up_sheet.dart';
import '../widgets/waveform_progress_bar.dart';
import '../widgets/basic_progress_bar.dart';
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
  bool _loadingLyrics = false;
  bool _autoScrollEnabled = true;
  String? _lastSongId;
  final ScrollController _lyricsScrollController = ScrollController();
  final GlobalKey _lyricsContainerKey = GlobalKey();
  final ValueNotifier<int> _currentLyricIndexNotifier = ValueNotifier<int>(-1);
  late TapGestureRecognizer _artistRecognizer;
  late TapGestureRecognizer _albumRecognizer;
  late AnimationController _playPauseController;

  StreamSubscription? _sequenceSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;

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
    _sequenceSubscription = player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      final String? songId = tag is MediaItem ? tag.id : null;

      if (songId != _lastSongId) {
        if (mounted) {
          setState(() {
            _lastSongId = songId;
            _lyrics = null;
            _showLyrics = false;
            _loadingLyrics = false;
            _autoScrollEnabled = true;
            _currentLyricIndexNotifier.value = -1;
          });
        }
      }
    });

    // Sync animation controller with player state
    _playerStateSubscription = player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
    });

    _positionSubscription = player.positionStream.listen((position) {
      if (!mounted) return;
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
        _lyricOffsets == null ||
        !_showLyrics) {
      return;
    }

    final currentScroll = _lyricsScrollController.offset;
    final targetScroll =
        _lyricOffsets![_currentLyricIndexNotifier.value] - 120; // 120 is padding

    // If current scroll is within 150px of target, re-enable sync
    if ((currentScroll - targetScroll).abs() < 150) {
      if (mounted && !_autoScrollEnabled) {
        setState(() => _autoScrollEnabled = true);
        _scrollToCurrentLyric();
      }
    }
  }

  void _scrollToCurrentLyric() {
    if (_lyricOffsets != null &&
        _currentLyricIndexNotifier.value >= 0 &&
        _currentLyricIndexNotifier.value < _lyricOffsets!.length) {
      final targetOffset =
          (_lyricOffsets![_currentLyricIndexNotifier.value] - 120)
              .clamp(0.0, _lyricsScrollController.position.maxScrollExtent);

      _lyricsScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _sequenceSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _currentLyricIndexNotifier.dispose();
    _playPauseController.dispose();
    _lyricsScrollController.dispose();
    _artistRecognizer.dispose();
    _albumRecognizer.dispose();
    super.dispose();
  }

  List<double>? _lyricOffsets;

  void _calculateLyricOffsets() {
    if (_lyrics == null || _lyrics!.isEmpty) return;

    final containerContext = _lyricsContainerKey.currentContext;
    if (containerContext == null) return;

    final RenderBox containerBox =
        containerContext.findRenderObject() as RenderBox;
    final maxWidth = containerBox.size.width;

    double currentOffset = 0;
    final List<double> offsets = [];

    for (final line in _lyrics!) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxWidth - 48);

      final height = textPainter.size.height + 24; // 12 * 2 padding
      offsets.add(currentOffset + height / 2);
      currentOffset += height;
    }

    setState(() {
      _lyricOffsets = offsets;
    });
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
      final currentSource = sequenceState.currentSource;
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
              _loadingLyrics = false;
            });

            // Find current position and scroll after first build
            _updateCurrentLyricIndex(player.position);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _showLyrics) {
                _calculateLyricOffsets();
                _scrollToCurrentLyric();
              }
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
        if (mounted && _showLyrics) {
          if (_lyricOffsets == null) _calculateLyricOffsets();
          _scrollToCurrentLyric();
        }
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

  Widget _buildOverlayButton({
    required Widget icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: IconButton(
            icon: icon,
            onPressed: onPressed,
            color: color ?? Colors.white,
            iconSize: 24,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  // _buildGlassControls removed.
  // _buildBlurButton removed.
  // _buildBottomDock removed.

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          player.positionStream,
          player.bufferedPositionStream,
          player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);

    return Theme(
      data: AppTheme.getPlayerTheme(themeState, themeState.extractedColor),
      child: Builder(builder: (context) {
        final isDesktop = !kIsWeb &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
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
                    if (metadata != null)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: AlbumArtImage(
                                  url: metadata.artUri?.toString() ?? '',
                                  filename: metadata.id,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 600,
                                ),
                              ),
                              Positioned.fill(
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.6),
                                          Colors.black.withValues(alpha: 0.85),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 40, 24, 80),
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
                                child: LayoutBuilder(
                                    builder: (context, constraints) {
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
                                      duration:
                                          const Duration(milliseconds: 500),
                                      switchInCurve: Curves.easeOutQuart,
                                      switchOutCurve: Curves.easeInQuart,
                                      transitionBuilder: (child, animation) {
                                        final isLyrics = child is ClipRRect;

                                        return FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: isLyrics ? 0.92 : 1.05,
                                              end: 1.0,
                                            ).animate(animation),
                                            child: child,
                                          ),
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
                                                      alignment:
                                                          Alignment.center,
                                                      children: [
                                                        // Main Image
                                                        Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        28),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withValues(
                                                                        alpha:
                                                                            0.4),
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
                                                                    .circular(
                                                                        28),
                                                            child:
                                                                AlbumArtImage(
                                                              key: ValueKey(
                                                                  'art_${metadata.id}'),
                                                              url: metadata
                                                                      .artUri
                                                                      ?.toString() ??
                                                                  '',
                                                              filename:
                                                                  metadata.id,
                                                              width: constraints
                                                                  .maxWidth,
                                                              height:
                                                                  constraints
                                                                      .maxWidth,
                                                              cacheWidth: 800,
                                                              fit: BoxFit.cover,
                                                            ),
                                                          ),
                                                        ),
                                                        // Overlay Controls (Lyrics / Queue)
                                                        if (metadata.extras?[
                                                                'hasLyrics'] ??
                                                            false)
                                                          Positioned(
                                                            bottom: 12,
                                                            left: 12,
                                                            child:
                                                                _buildOverlayButton(
                                                              icon: const Icon(Icons
                                                                  .lyrics_outlined),
                                                              color: _showLyrics
                                                                  ? Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary
                                                                  : Colors
                                                                      .white,
                                                              onPressed:
                                                                  _toggleLyrics,
                                                            ),
                                                          ),
                                                        Positioned(
                                                          bottom: 12,
                                                          right: 12,
                                                          child:
                                                              _buildOverlayButton(
                                                            icon: const Icon(Icons
                                                                .queue_music),
                                                            onPressed: () {
                                                              showModalBottomSheet(
                                                                context:
                                                                    context,
                                                                backgroundColor:
                                                                    Colors
                                                                        .transparent,
                                                                builder:
                                                                    (context) =>
                                                                        Theme(
                                                                  data: AppTheme.getPlayerTheme(
                                                                      themeState,
                                                                      themeState
                                                                          .extractedColor),
                                                                  child:
                                                                      const NextUpSheet(),
                                                                ),
                                                              );
                                                            },
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
                                                  Positioned.fill(
                                                    child: Container(
                                                      color: Colors.black45,
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
                                                                    fontSize:
                                                                        18),
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
                                                              child: ListView.builder(
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
                                                                  final hasTime =
                                                                      _lyrics![index]
                                                                              .time !=
                                                                          Duration
                                                                              .zero;
                                                                  return ValueListenableBuilder<
                                                                      int>(
                                                                    valueListenable:
                                                                        _currentLyricIndexNotifier,
                                                                    builder: (context,
                                                                        currentIndex,
                                                                        child) {
                                                                      final isCurrent =
                                                                          index ==
                                                                              currentIndex;
                                                                      return RepaintBoundary(
                                                                        child:
                                                                            InkWell(
                                                                          onTap: hasTime
                                                                              ? () {
                                                                                  player.seek(_lyrics![index].time);
                                                                                  setState(() => _autoScrollEnabled = true);
                                                                                }
                                                                              : null,
                                                                          child:
                                                                              Padding(
                                                                            padding: const EdgeInsets
                                                                                .symmetric(
                                                                                horizontal: 24,
                                                                                vertical: 12),
                                                                            child:
                                                                                Text(
                                                                              _lyrics![index].text,
                                                                              textAlign:
                                                                                  TextAlign.center,
                                                                              style:
                                                                                  TextStyle(
                                                                                fontSize: 26,
                                                                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                                                                color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.3),
                                                                                height: 1.3,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                  // Overlay Controls in Lyrics Mode (Lyrics / Queue)
                                                  if (metadata.extras?[
                                                          'hasLyrics'] ??
                                                      false)
                                                    Positioned(
                                                      bottom: 12,
                                                      left: 12,
                                                      child:
                                                          _buildOverlayButton(
                                                        icon: const Icon(Icons
                                                            .lyrics_outlined),
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                        onPressed:
                                                            _toggleLyrics,
                                                      ),
                                                    ),
                                                  Positioned(
                                                    bottom: 12,
                                                    right: 12,
                                                    child: _buildOverlayButton(
                                                      icon: const Icon(
                                                          Icons.queue_music),
                                                      onPressed: () {
                                                        showModalBottomSheet(
                                                          context: context,
                                                          backgroundColor:
                                                              Colors
                                                                  .transparent,
                                                          builder: (context) =>
                                                              Theme(
                                                            data: AppTheme
                                                                .getPlayerTheme(
                                                                    themeState,
                                                                    themeState
                                                                        .extractedColor),
                                                            child:
                                                                const NextUpSheet(),
                                                          ),
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
                            RepaintBoundary(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          metadata.title,
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.5),
                                          textAlign: TextAlign.left,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        RichText(
                                          textAlign: TextAlign.left,
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
                                                text: metadata.artist ??
                                                    'Unknown Artist',
                                                recognizer: _artistRecognizer
                                                  ..onTap = () =>
                                                      _navigateToArtist(
                                                          metadata.artist ??
                                                              'Unknown Artist'),
                                              ),
                                              const TextSpan(text: ' • '),
                                              TextSpan(
                                                text: metadata.album ??
                                                    'Unknown Album',
                                                recognizer: _albumRecognizer
                                                  ..onTap = () =>
                                                      _navigateToAlbum(
                                                          metadata.album ??
                                                              'Unknown Album'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Consumer(
                                    builder: (context, ref, child) {
                                      final isFav = ref.watch(
                                          userDataProvider.select((s) =>
                                              s.isFavorite(metadata.id)));
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
                                              : Colors.white,
                                          onPressed: () {
                                            ref
                                                .read(userDataProvider.notifier)
                                                .toggleFavorite(metadata.id);
                                          },
                                          iconSize: 28,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],

                          RepaintBoundary(
                            child: StreamBuilder<PositionData>(
                              stream: _positionDataStream,
                              builder: (context, snapshot) {
                                if (metadata == null) {
                                  return const SizedBox.shrink();
                                }
                                final positionData = snapshot.data;
                                final showWaveform =
                                    ref.watch(settingsProvider).showWaveform;

                                if (showWaveform) {
                                  return WaveformProgressBar(
                                    filename: metadata.id,
                                    path: metadata.extras?['audioPath'] ?? '',
                                    progress:
                                        positionData?.position ?? Duration.zero,
                                    total:
                                        positionData?.duration ?? Duration.zero,
                                    onSeek: player.seek,
                                  );
                                } else {
                                  return BasicProgressBar(
                                    progress:
                                        positionData?.position ?? Duration.zero,
                                    total:
                                        positionData?.duration ?? Duration.zero,
                                    onSeek: player.seek,
                                  );
                                }
                              },
                            ),
                          ),
                          if (isDesktop || isIPad) ...[
                            const SizedBox(height: 16),
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
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
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
                          // Main Controls
                          RepaintBoundary(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Repeat
                                StreamBuilder<LoopMode>(
                                  stream: player.loopModeStream,
                                  builder: (context, snapshot) {
                                    final loopMode =
                                        snapshot.data ?? LoopMode.off;
                                    IconData iconData = Icons.repeat;
                                    Color color = Colors.white60;
                                    if (loopMode == LoopMode.one) {
                                      iconData = Icons.repeat_one;
                                      color =
                                          Theme.of(context).colorScheme.primary;
                                    } else if (loopMode == LoopMode.all) {
                                      iconData = Icons.repeat;
                                      color =
                                          Theme.of(context).colorScheme.primary;
                                    }
                                    return IconButton(
                                      icon: Icon(iconData,
                                          color: color, size: 24),
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
                                            borderRadius:
                                                BorderRadius.circular(20),
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
                                        icon: const Icon(
                                            Icons.skip_next_rounded,
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
                  ),
                ],
              );
              },
            ),
          ),
        );
      }),
    );
  }
}

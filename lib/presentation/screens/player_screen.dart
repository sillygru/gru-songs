import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/album_art_image.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/audio_player_manager.dart';
import '../widgets/heart_context_menu.dart';
import '../widgets/waveform_progress_bar.dart';
import '../widgets/basic_progress_bar.dart';
import '../widgets/smooth_color_builder.dart';
import 'song_list_screen.dart';
import 'full_screen_lyrics.dart';
import 'next_up_screen.dart';

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
    with TickerProviderStateMixin {
  late AnimationController _expansionController;
  late AnimationController _controlsController;
  late Animation<double> _artScaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  static const Set<String> _videoExtensions = {
    '.mp4',
    '.m4v',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
    '.3gp',
  };

  bool _hasLyricsForCurrentSong = false;
  String? _lastSongId;
  int _lyricsAvailabilityRequestToken = 0;
  List<LyricLine>? _lyrics;
  late TapGestureRecognizer _artistRecognizer;
  late TapGestureRecognizer _albumRecognizer;
  late AnimationController _playPauseController;
  late AnimationController _dragController;
  Animation<double>? _dragAnimation;
  double _dragOffsetY = 0.0;
  bool _isClosingPlayer = false;
  final ScrollController _lyricsScrollController = ScrollController();

  StreamSubscription? _sequenceSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  VideoPlayerController? _videoController;
  String? _videoSongId;
  bool _isVideoReady = false;

  AudioPlayerManager? _audioManagerInstance;
  AudioPlayer get player => ref.read(audioPlayerManagerProvider).player;
  AudioPlayerManager get _audioManager =>
      _audioManagerInstance ??= ref.read(audioPlayerManagerProvider)!;

  @override
  void initState() {
    super.initState();
    _expansionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _controlsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _artScaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expansionController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expansionController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));
    _slideAnimation = Tween<double>(
      begin: 30.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _expansionController,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _expansionController.forward();
        _controlsController.forward();
      }
    });

    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _dragController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )
      ..addListener(() {
        final animation = _dragAnimation;
        if (!mounted || animation == null) return;
        setState(() {
          _dragOffsetY = animation.value;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _dragAnimation = null;
        }
      });
    _artistRecognizer = TapGestureRecognizer();
    _albumRecognizer = TapGestureRecognizer();
    _sequenceSubscription = player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      final mediaItem = tag is MediaItem ? tag : null;
      final String? songId = mediaItem?.id;
      final metadataHasLyrics = mediaItem?.extras?['hasLyrics'] == true;

      if (songId != _lastSongId) {
        if (mounted) {
          setState(() {
            _lastSongId = songId;
            _lyrics = null;
            _hasLyricsForCurrentSong = metadataHasLyrics;
          });
        }
        _refreshLyricsAvailability(songId,
            metadataHasLyrics: metadataHasLyrics);
      }
      _syncVideoForCurrentTrack(mediaItem);
    });

    _playerStateSubscription = player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
      _syncVideoPlaybackState();
    });

    _positionSubscription = player.positionStream.listen((position) {
      if (!mounted) return;
      _syncVideoPosition(position);
    });
    _audioManager.effectiveMediaModeNotifier
        .addListener(_handleMediaModeChanged);
  }

  void _openNextUpScreen(BuildContext context, ThemeState themeState) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => Theme(
          data: AppTheme.getPlayerTheme(themeState, themeState.extractedColor),
          child: const NextUpScreen(),
        ),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curve),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.7, end: 1.0).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _sequenceSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioManagerInstance?.effectiveMediaModeNotifier
        .removeListener(_handleMediaModeChanged);
    unawaited(_disposeVideoController(notify: false));
    _playPauseController.dispose();
    _dragController.dispose();
    _expansionController.dispose();
    _controlsController.dispose();
    _lyricsScrollController.dispose();
    _artistRecognizer.dispose();
    _albumRecognizer.dispose();
    super.dispose();
  }

  void _handleMediaModeChanged() {
    final tag = player.sequenceState?.currentSource?.tag;
    final mediaItem = tag is MediaItem ? tag : null;
    unawaited(_syncVideoForCurrentTrack(mediaItem));
  }

  bool _hasVideoExtension(String path) {
    final lowerPath = path.toLowerCase();
    return _videoExtensions.any(lowerPath.endsWith);
  }

  String? _resolveCoverUrl(MediaItem? mediaItem) {
    if (mediaItem == null) return null;

    final song = _findSongById(mediaItem.id);
    if (song?.coverUrl != null && song!.coverUrl!.isNotEmpty) {
      return song.coverUrl;
    }

    final artUri = mediaItem.artUri;
    if (artUri == null) return null;
    return artUri.toString();
  }

  ({String songId, bool hasVideo, String? mediaPath}) _resolveTrackMedia(
      MediaItem? mediaItem) {
    final songId = mediaItem?.id ?? '';
    final song = songId.isNotEmpty ? _findSongById(songId) : null;
    final extras = mediaItem?.extras;

    final String? mediaPath = song?.url ??
        (extras?['audioPath'] as String?) ??
        (extras?['remoteUrl'] as String?);

    final bool hasVideo = song?.hasVideo == true ||
        (song == null &&
            ((extras?['hasVideo'] == true) ||
                (mediaPath != null && _hasVideoExtension(mediaPath))));

    return (songId: songId, hasVideo: hasVideo, mediaPath: mediaPath);
  }

  Song? _findSongById(String songId) {
    final songs = ref.read(songsProvider).asData?.value ?? [];
    for (final song in songs) {
      if (song.filename == songId) return song;
    }
    return null;
  }

  Future<void> _refreshLyricsAvailability(
    String? songId, {
    required bool metadataHasLyrics,
  }) async {
    final requestToken = ++_lyricsAvailabilityRequestToken;

    if (songId == null) {
      if (mounted) {
        setState(() => _hasLyricsForCurrentSong = false);
      }
      return;
    }

    final currentSong = _findSongById(songId);
    if (currentSong == null) return;

    bool hasLyrics = metadataHasLyrics;
    try {
      hasLyrics = await ref.read(songRepositoryProvider).hasLyrics(currentSong);
    } catch (_) {
      hasLyrics = metadataHasLyrics;
    }

    if (!mounted || requestToken != _lyricsAvailabilityRequestToken) return;
    if (_lastSongId != songId) return;
    setState(() => _hasLyricsForCurrentSong = hasLyrics);
  }

  Future<void> _syncVideoForCurrentTrack(MediaItem? mediaItem) async {
    final track = _resolveTrackMedia(mediaItem);
    final isVideoMode =
        _audioManager.effectiveMediaMode == PlaybackMediaMode.video;

    if (!isVideoMode ||
        track.songId.isEmpty ||
        !track.hasVideo ||
        track.mediaPath == null ||
        track.mediaPath!.isEmpty) {
      await _disposeVideoController();
      return;
    }

    if (_videoSongId == track.songId &&
        _videoController != null &&
        _isVideoReady) {
      _syncVideoPlaybackState();
      _syncVideoPosition(player.position);
      return;
    }

    await _disposeVideoController();

    // Build the controller for either a local file or a remote URL.
    final VideoPlayerController controller;
    final bool isNetworkPath = track.mediaPath!.startsWith('http://') ||
        track.mediaPath!.startsWith('https://');

    if (isNetworkPath) {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(track.mediaPath!),
      );
    } else {
      controller = VideoPlayerController.file(File(track.mediaPath!));
    }

    try {
      // Listen before initializing so we catch any size/state updates that
      // fire during or after initialization.
      controller.addListener(_onVideoControllerUpdated);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0.0);
      await controller.seekTo(player.position);
      _videoController = controller;
      _videoSongId = track.songId;
      _isVideoReady = true;
      _syncVideoPlaybackState();
      if (mounted) setState(() {});
    } catch (_) {
      controller.removeListener(_onVideoControllerUpdated);
      await controller.dispose();
      _videoController = null;
      _videoSongId = null;
      _isVideoReady = false;
      if (mounted) setState(() {});
    }
  }

  void _syncVideoPlaybackState() {
    final controller = _videoController;
    if (controller == null || !_isVideoReady) return;
    if (_audioManager.effectiveMediaMode != PlaybackMediaMode.video) {
      controller.pause();
      return;
    }
    if (player.playing) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _syncVideoPosition(Duration position) {
    final controller = _videoController;
    if (controller == null || !_isVideoReady) return;
    if (_audioManager.effectiveMediaMode != PlaybackMediaMode.video) return;

    final videoPosition = controller.value.position;
    if ((videoPosition - position).abs().inMilliseconds > 350) {
      controller.seekTo(position);
    }
  }

  Future<void> _disposeVideoController({bool notify = true}) async {
    final controller = _videoController;
    _videoController = null;
    _videoSongId = null;
    _isVideoReady = false;
    if (controller != null) {
      controller.removeListener(_onVideoControllerUpdated);
      await controller.dispose();
    }
    if (notify && mounted) setState(() {});
  }

  /// Called whenever the [VideoPlayerController]'s value changes (size,
  /// playback state, etc.). Triggers a rebuild so the video widget appears
  /// as soon as the first frame is decoded.
  void _onVideoControllerUpdated() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildMediaModePill(MediaItem metadata) {
    final hasVideo = _resolveTrackMedia(metadata).hasVideo;

    return ValueListenableBuilder<PlaybackMediaMode>(
      valueListenable: _audioManager.effectiveMediaModeNotifier,
      builder: (context, effectiveMode, _) {
        final bool isAudio = effectiveMode == PlaybackMediaMode.audio;

        return Container(
          width: 140, // Slightly wider for better breathing room
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Stack(
            children: [
              // Sliding background pill
              AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment:
                    isAudio ? Alignment.centerLeft : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildModeSegment(
                      label: 'Audio',
                      isSelected: isAudio,
                      onTap: () async {
                        await _audioManager
                            .setPreferredMediaMode(PlaybackMediaMode.audio);
                        await _syncVideoForCurrentTrack(metadata);
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildModeSegment(
                      label: 'Video',
                      isSelected: !isAudio,
                      isEnabled: hasVideo,
                      onTap: hasVideo
                          ? () async {
                              await _audioManager.setPreferredMediaMode(
                                  PlaybackMediaMode.video);
                              await _syncVideoForCurrentTrack(metadata);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSegment({
    required String label,
    required bool isSelected,
    bool isEnabled = true,
    Future<void> Function()? onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled && onTap != null ? () => unawaited(onTap()) : null,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: !isEnabled
                ? Colors.white24
                : (isSelected ? Colors.white : Colors.white60),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
          child: Text(label),
        ),
      ),
    );
  }

  void _toggleLyrics() async {
    if (!_hasLyricsForCurrentSong) return;

    final sequenceState = player.sequenceState;
    final currentSource = sequenceState?.currentSource;
    final tag = currentSource?.tag;
    if (tag is MediaItem) {
      final songs = ref.read(songsProvider).asData?.value ?? [];
      final currentSong = songs.cast<Song?>().firstWhere(
            (s) => s?.filename == tag.id,
            orElse: () => null,
          );
      if (currentSong == null) return;

      List<LyricLine> parsedLyrics = _lyrics ?? [];
      if (parsedLyrics.isEmpty) {
        final repo = ref.read(songRepositoryProvider);
        final lyricsContent = await repo.getLyrics(currentSong);
        if (lyricsContent != null) {
          parsedLyrics = LyricLine.parse(lyricsContent);
          _lyrics = parsedLyrics;
        }
      }

      if (mounted && parsedLyrics.isNotEmpty) {
        final themeState = ref.read(themeProvider);
        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) {
              return FullScreenLyrics(
                songId: currentSong.filename,
                songTitle: currentSong.title,
                songArtist: currentSong.artist.isEmpty
                    ? 'Unknown Artist'
                    : currentSong.artist,
                lyrics: parsedLyrics,
                extractedColor: themeState.extractedColor,
                initialPosition: player.position,
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;

              var tween = Tween(begin: begin, end: end).chain(
                CurveTween(curve: curve),
              );

              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
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
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
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
    );
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          player.positionStream,
          player.bufferedPositionStream,
          player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  double _dismissDistance(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.36;

  Future<void> _animateDragTo(
    double target, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    _dragController.stop();
    final begin = _dragOffsetY;
    final end = target.clamp(0.0, MediaQuery.of(context).size.height);
    final distance = (begin - end).abs();
    final computedDuration = duration ??
        Duration(
            milliseconds:
                (120 + (distance * 0.18)).clamp(120.0, 260.0).round());
    _dragAnimation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(
      parent: _dragController,
      curve: curve,
    ));
    _dragController.duration = computedDuration;
    await _dragController.forward(from: 0);
  }

  Future<void> _dismissPlayer() async {
    if (_isClosingPlayer || !mounted) return;
    _isClosingPlayer = true;
    _controlsController.reverse();
    _expansionController.reverse();
    final dismissTarget = (_dragOffsetY).clamp(
      MediaQuery.of(context).size.height * 0.35,
      MediaQuery.of(context).size.height,
    );
    await _animateDragTo(
      dismissTarget,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeInCubic,
    );
    if (mounted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onDismissDragStart(DragStartDetails details) {
    if (_isClosingPlayer) return;
    _dragController.stop();
  }

  void _onDismissDragUpdate(DragUpdateDetails details) {
    if (_isClosingPlayer) return;
    final delta = details.primaryDelta ?? 0.0;
    if (delta < 0 && _dragOffsetY <= 0) return;
    setState(() {
      _dragOffsetY = (_dragOffsetY + delta).clamp(0.0, double.infinity);
    });
  }

  void _onDismissDragEnd(DragEndDetails details) {
    if (_isClosingPlayer) return;
    final velocityY = details.primaryVelocity ?? 0.0;
    final progress = (_dragOffsetY / _dismissDistance(context)).clamp(0.0, 1.0);
    final shouldDismiss = progress > 0.25 || velocityY > 1100;

    if (shouldDismiss) {
      unawaited(_dismissPlayer());
      return;
    }
    unawaited(_animateDragTo(0.0));
  }

  /// Builds the artwork / video panel. The aspect ratio and corner radius
  /// animate smoothly whenever the effective media mode changes so the panel
  /// snaps from square album-art to the video's native shape (e.g. 16:9).
  Widget _buildArtPanel(
    BuildContext context,
    BoxConstraints constraints,
    MediaItem metadata,
    ThemeState themeState,
  ) {
    final canShowVideo =
        _audioManager.effectiveMediaMode == PlaybackMediaMode.video &&
            _isVideoReady &&
            _videoController != null &&
            _videoSongId == metadata.id &&
            _videoController!.value.isInitialized;

    final targetAspectRatio =
        canShowVideo ? _videoController!.value.aspectRatio : 1.0;
    final targetRadius = canShowVideo ? 8.0 : 28.0;

    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _artScaleAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(CurvedAnimation(
              parent: _playPauseController,
              curve: Curves.easeOutBack,
            )),
            child: TweenAnimationBuilder<double>(
              // TweenAnimationBuilder will automatically start from the last
              // animated value when `end` changes — giving us a free smooth
              // transition between square and the video's aspect ratio.
              tween: Tween<double>(begin: 1.0, end: targetAspectRatio),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOut,
              builder: (context, aspectRatio, _) {
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 28.0, end: targetRadius),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeInOut,
                  builder: (context, radius, _) {
                    return AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Hero(
                        tag: 'now_playing_art_${metadata.id}',
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Main art / video container.
                            Positioned.fill(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeInOut,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(radius),
                                  boxShadow: canShowVideo
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.4),
                                            blurRadius: 25,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(radius),
                                  child: canShowVideo
                                      ? SizedBox.expand(
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            clipBehavior: Clip.hardEdge,
                                            child: SizedBox(
                                              width: _videoController!
                                                  .value.size.width,
                                              height: _videoController!
                                                  .value.size.height,
                                              child: VideoPlayer(
                                                  _videoController!),
                                            ),
                                          ),
                                        )
                                      : AlbumArtImage(
                                          key: ValueKey('art_${metadata.id}'),
                                          url: _resolveCoverUrl(metadata) ?? '',
                                          filename: metadata.id,
                                          width: constraints.maxWidth,
                                          height: constraints.maxWidth,
                                          cacheWidth: 800,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                            ),
                            // Overlay: lyrics toggle.
                            if (_hasLyricsForCurrentSong)
                              Positioned(
                                bottom: 12,
                                left: 12,
                                child: _buildOverlayButton(
                                  icon: const Icon(Icons.lyrics_outlined),
                                  color: Colors.white,
                                  onPressed: _toggleLyrics,
                                ),
                              ),
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: _buildOverlayButton(
                                icon: const Icon(Icons.queue_music),
                                onPressed: () =>
                                    _openNextUpScreen(context, themeState),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final dragProgress =
        (_dragOffsetY / _dismissDistance(context)).clamp(0.0, 1.0);
    final dynamicRadius = 32.0 + (dragProgress * 16.0);
    final scale = 1.0 - (dragProgress * 0.035);

    return PopScope(
      canPop: _expansionController.isCompleted,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_dismissPlayer());
      },
      child: AnimatedTheme(
        data: AppTheme.getPlayerTheme(themeState, themeState.extractedColor),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        child: Builder(builder: (context) {
          final isDesktop = !kIsWeb &&
              (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
          final isIPad = !kIsWeb &&
              Platform.isIOS &&
              MediaQuery.of(context).size.shortestSide >= 600;

          return Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: _onDismissDragStart,
              onVerticalDragUpdate: _onDismissDragUpdate,
              onVerticalDragEnd: _onDismissDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffsetY),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: 1.0 - (dragProgress * 0.12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(dynamicRadius),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(dynamicRadius),
                        ),
                        child: StreamBuilder<SequenceState?>(
                          stream: player.sequenceStateStream,
                          builder: (context, snapshot) {
                            final state = snapshot.data;
                            final metadata =
                                state?.currentSource?.tag as MediaItem?;

                            return Stack(
                              children: [
                                if (metadata != null)
                                  Positioned.fill(
                                    child: RepaintBoundary(
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: AlbumArtImage(
                                              url: _resolveCoverUrl(metadata) ??
                                                  '',
                                              filename: metadata.id,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                  sigmaX: 25, sigmaY: 25),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.black.withValues(
                                                          alpha: 0.5),
                                                      Colors.black.withValues(
                                                          alpha: 0.8),
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
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 40, 24, 80),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 4,
                                          margin:
                                              const EdgeInsets.only(bottom: 24),
                                          decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(2)),
                                        ),
                                        if (metadata != null) ...[
                                          _buildMediaModePill(metadata),
                                          const SizedBox(height: 16),
                                        ],
                                        if (metadata != null) ...[
                                          Expanded(
                                            child: RepaintBoundary(
                                              child: LayoutBuilder(builder:
                                                  (context, constraints) {
                                                return GestureDetector(
                                                  onVerticalDragUpdate:
                                                      (details) {
                                                    if (details.primaryDelta! <
                                                            -5 &&
                                                        _hasLyricsForCurrentSong) {
                                                      _toggleLyrics();
                                                    }
                                                  },
                                                  child: _buildArtPanel(
                                                    context,
                                                    constraints,
                                                    metadata,
                                                    themeState,
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                          RepaintBoundary(
                                            child: FadeTransition(
                                              opacity: _fadeAnimation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, 0.3),
                                                  end: Offset.zero,
                                                ).animate(CurvedAnimation(
                                                  parent: _expansionController,
                                                  curve: const Interval(
                                                      0.3, 0.7,
                                                      curve:
                                                          Curves.easeOutCubic),
                                                )),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            metadata.title,
                                                            style: const TextStyle(
                                                                fontSize: 26,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                letterSpacing:
                                                                    -0.5),
                                                            textAlign:
                                                                TextAlign.left,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          RichText(
                                                            textAlign:
                                                                TextAlign.left,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            text: TextSpan(
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontFamily: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodyMedium
                                                                    ?.fontFamily,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onSurfaceVariant
                                                                    .withValues(
                                                                        alpha:
                                                                            0.7),
                                                              ),
                                                              children: [
                                                                TextSpan(
                                                                  text: metadata
                                                                          .artist ??
                                                                      'Unknown Artist',
                                                                  recognizer: _artistRecognizer
                                                                    ..onTap = () =>
                                                                        _navigateToArtist(metadata.artist ??
                                                                            'Unknown Artist'),
                                                                ),
                                                                const TextSpan(
                                                                    text:
                                                                        ' • '),
                                                                TextSpan(
                                                                  text: metadata
                                                                          .album ??
                                                                      'Unknown Album',
                                                                  recognizer: _albumRecognizer
                                                                    ..onTap = () =>
                                                                        _navigateToAlbum(metadata.album ??
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
                                                      builder: (context, ref,
                                                          child) {
                                                        final isFav = ref.watch(
                                                            userDataProvider
                                                                .select((s) => s
                                                                    .isFavorite(
                                                                        metadata
                                                                            .id)));
                                                        return GestureDetector(
                                                          onLongPress: () {
                                                            showHeartContextMenu(
                                                              context: context,
                                                              ref: ref,
                                                              songFilename:
                                                                  metadata.id,
                                                              songTitle:
                                                                  metadata
                                                                      .title,
                                                            );
                                                          },
                                                          child: IconButton(
                                                            icon: Icon(isFav
                                                                ? Icons.favorite
                                                                : Icons
                                                                    .favorite_border),
                                                            color: isFav
                                                                ? Colors
                                                                    .redAccent
                                                                : Colors.white,
                                                            onPressed: () {
                                                              ref
                                                                  .read(userDataProvider
                                                                      .notifier)
                                                                  .toggleFavorite(
                                                                      metadata
                                                                          .id);
                                                            },
                                                            iconSize: 28,
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
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
                                              final positionData =
                                                  snapshot.data;
                                              final showWaveform = ref
                                                  .watch(settingsProvider)
                                                  .showWaveform;
                                              final duration =
                                                  positionData?.duration ??
                                                      Duration.zero;
                                              final currentPosition =
                                                  positionData?.position ??
                                                      Duration.zero;

                                              if (showWaveform) {
                                                return WaveformProgressBar(
                                                  filename: metadata.id,
                                                  path: metadata.extras?[
                                                          'audioPath'] ??
                                                      '',
                                                  progress: currentPosition,
                                                  total: duration,
                                                  onSeek: player.seek,
                                                );
                                              } else {
                                                return BasicProgressBar(
                                                  progress: currentPosition,
                                                  total: duration,
                                                  onSeek: player.seek,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        if (isDesktop || isIPad) ...[
                                          const SizedBox(height: 16),
                                          SmoothColorBuilder(
                                            targetColor: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            builder: (context, sliderColor) {
                                              return Row(
                                                children: [
                                                  const Icon(Icons.volume_down,
                                                      size: 20,
                                                      color: Colors.white60),
                                                  Expanded(
                                                    child:
                                                        StreamBuilder<double>(
                                                      stream:
                                                          player.volumeStream,
                                                      builder:
                                                          (context, snapshot) {
                                                        return Slider(
                                                          value:
                                                              snapshot.data ??
                                                                  1.0,
                                                          activeColor:
                                                              sliderColor,
                                                          inactiveColor:
                                                              Colors.white10,
                                                          onChanged:
                                                              player.setVolume,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  const Icon(Icons.volume_up,
                                                      size: 20,
                                                      color: Colors.white60),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                        const SizedBox(height: 32),
                                        FadeTransition(
                                          opacity: _controlsController,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, 0.4),
                                              end: Offset.zero,
                                            ).animate(CurvedAnimation(
                                              parent: _controlsController,
                                              curve: const Interval(0.4, 0.85,
                                                  curve: Curves.easeOutCubic),
                                            )),
                                            child: RepaintBoundary(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  StreamBuilder<LoopMode>(
                                                    stream:
                                                        player.loopModeStream,
                                                    builder:
                                                        (context, snapshot) {
                                                      final loopMode =
                                                          snapshot.data ??
                                                              LoopMode.off;
                                                      IconData iconData =
                                                          Icons.repeat;
                                                      final bool isActive =
                                                          loopMode ==
                                                                  LoopMode
                                                                      .one ||
                                                              loopMode ==
                                                                  LoopMode.all;
                                                      return SmoothColorBuilder(
                                                        targetColor: isActive
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Colors.white60,
                                                        builder:
                                                            (context, color) {
                                                          if (loopMode ==
                                                              LoopMode.one) {
                                                            iconData = Icons
                                                                .repeat_one;
                                                          }
                                                          return IconButton(
                                                            icon: Icon(iconData,
                                                                color: color,
                                                                size: 24),
                                                            onPressed: () {
                                                              final nextMode = LoopMode
                                                                  .values[(loopMode
                                                                          .index +
                                                                      1) %
                                                                  LoopMode
                                                                      .values
                                                                      .length];
                                                              player
                                                                  .setLoopMode(
                                                                      nextMode);
                                                            },
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                  SmoothColorBuilder(
                                                    targetColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                    builder:
                                                        (context, buttonColor) {
                                                      return Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Container(
                                                            height: 55,
                                                            width: 55,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: buttonColor
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16),
                                                            ),
                                                            child: IconButton(
                                                              icon: const Icon(
                                                                  Icons
                                                                      .skip_previous_rounded,
                                                                  size: 26),
                                                              color:
                                                                  Colors.white,
                                                              onPressed: () {
                                                                if (player
                                                                        .position
                                                                        .inSeconds >
                                                                    3) {
                                                                  player.seek(
                                                                      Duration
                                                                          .zero);
                                                                } else {
                                                                  player
                                                                      .seekToPrevious();
                                                                }
                                                              },
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 12),
                                                          StreamBuilder<
                                                              PlayerState>(
                                                            stream: player
                                                                .playerStateStream,
                                                            builder: (context,
                                                                snapshot) {
                                                              final playerState =
                                                                  snapshot.data;
                                                              final playing =
                                                                  playerState
                                                                          ?.playing ??
                                                                      false;
                                                              return Container(
                                                                height: 75,
                                                                width: 100,
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: buttonColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.8),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              20),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: buttonColor.withValues(
                                                                          alpha:
                                                                              0.3),
                                                                      blurRadius:
                                                                          15,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              4),
                                                                    ),
                                                                  ],
                                                                ),
                                                                child:
                                                                    IconButton(
                                                                  icon:
                                                                      AnimatedIcon(
                                                                    icon: AnimatedIcons
                                                                        .play_pause,
                                                                    progress:
                                                                        _playPauseController,
                                                                    size: 42,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                  onPressed: playing
                                                                      ? player
                                                                          .pause
                                                                      : player
                                                                          .play,
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                          const SizedBox(
                                                              width: 12),
                                                          Container(
                                                            height: 55,
                                                            width: 55,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: buttonColor
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16),
                                                            ),
                                                            child: IconButton(
                                                              icon: const Icon(
                                                                  Icons
                                                                      .skip_next_rounded,
                                                                  size: 26),
                                                              color:
                                                                  Colors.white,
                                                              onPressed: player
                                                                      .hasNext
                                                                  ? player
                                                                      .seekToNext
                                                                  : null,
                                                            ),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                  ValueListenableBuilder<bool>(
                                                    valueListenable: ref
                                                        .read(
                                                            audioPlayerManagerProvider)
                                                        .shuffleNotifier,
                                                    builder: (context,
                                                        isShuffled, child) {
                                                      return SmoothColorBuilder(
                                                        targetColor: isShuffled
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Colors.white60,
                                                        builder:
                                                            (context, color) {
                                                          return IconButton(
                                                            icon: Icon(
                                                                Icons.shuffle,
                                                                size: 24,
                                                                color: color),
                                                            onLongPress: () =>
                                                                _showShuffleSettings(
                                                                    context,
                                                                    ref),
                                                            onPressed:
                                                                () async {
                                                              await ref
                                                                  .read(
                                                                      audioPlayerManagerProvider)
                                                                  .toggleShuffle();
                                                            },
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
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
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

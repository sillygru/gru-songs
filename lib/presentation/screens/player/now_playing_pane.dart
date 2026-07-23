import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';

import '../../../domain/services/video_sync_policy.dart';
import '../../../models/song.dart';
import '../../../providers/providers.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/audio_player_manager.dart';
import '../../components/song_actions.dart';
import '../../tokens/player_tokens.dart';
import '../../widgets/album_art_image.dart';
import '../../widgets/beat_reactive_cover.dart';
import '../../widgets/heart_context_menu.dart';
import '../../widgets/now_playing_lyric_peek.dart';
import '../../widgets/player_motion.dart';

/// Center pane. Content only — the shell owns the backdrop, header, pill and
/// transport dock. Do not add a Scaffold, AppBar or background here.
class NowPlayingPane extends ConsumerStatefulWidget {
  final Song song;
  final Color accent;

  /// Owned by the shell — the cover shares it with the particle field.
  final PlayerMotionController motion;

  /// Marks the artwork box so the shell's glow layer can find it. The glow is
  /// painted up there rather than here so it can spill past this pane.
  final GlobalKey coverKey;

  /// Whether this pane is the one on screen. The pane is kept alive across
  /// swipes, so without this a video would go on decoding behind the Queue.
  final ValueListenable<bool> paneVisible;

  const NowPlayingPane({
    super.key,
    required this.song,
    required this.accent,
    required this.motion,
    required this.coverKey,
    required this.paneVisible,
  });

  @override
  ConsumerState<NowPlayingPane> createState() => _NowPlayingPaneState();
}

class _NowPlayingPaneState extends ConsumerState<NowPlayingPane>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final audioManager = ref.watch(audioPlayerManagerProvider);
    final coverSizing =
        ref.watch(settingsProvider.select((s) => s.coverSizingMode));

    // The cover is the flexible element: the title block is laid out in full
    // first and the artwork takes whatever is left. Sizing the cover up front
    // and scrolling the overflow is what used to clip the album line.
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverCap = constraints.maxHeight * PlayerTokens.coverMaxFraction;

        return Column(
          children: [
            const SizedBox(height: PlayerTokens.s4),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: PlayerTokens.s5),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final side = math
                        .min(box.maxWidth, box.maxHeight)
                        .clamp(0.0, coverCap);

                    return _CoverStage(
                      song: widget.song,
                      accent: widget.accent,
                      size: side,
                      boxWidth: box.maxWidth,
                      boxHeight: box.maxHeight,
                      coverSizing: coverSizing,
                      audioManager: audioManager,
                      motion: widget.motion,
                      coverKey: widget.coverKey,
                      paneVisible: widget.paneVisible,
                    );
                  },
                ),
              ),
            ),
            if (widget.song.hasVideo) ...[
              const SizedBox(height: PlayerTokens.s3),
              _VideoModeToggle(
                accent: widget.accent,
                audioManager: audioManager,
              ),
            ],
            const SizedBox(height: PlayerTokens.s4),
            _buildTitleBlock(context),
            const SizedBox(height: PlayerTokens.s2),
            NowPlayingLyricPeek(song: widget.song, accent: widget.accent),
            const SizedBox(height: PlayerTokens.s2),
          ],
        );
      },
    );
  }

  Widget _buildTitleBlock(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PlayerTokens.s5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PlayerTokens.paneTitle(context).copyWith(fontSize: 22),
                ),
                const SizedBox(height: PlayerTokens.s1),
                Text(
                  widget.song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PlayerTokens.trackSubtitle(context)
                      .copyWith(fontSize: 14),
                ),
                if (widget.song.album.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.song.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PlayerTokens.meta(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: PlayerTokens.s3),
          _FavoriteButton(song: widget.song, accent: widget.accent),
        ],
      ),
    );
  }
}

/// Favorite lives here rather than only in the quick action row: it is the one
/// action people expect to find without configuring anything, and the quick
/// action row can be reordered or turned off entirely.
class _FavoriteButton extends ConsumerStatefulWidget {
  final Song song;
  final Color accent;

  const _FavoriteButton({required this.song, required this.accent});

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pop;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringFade;
  bool _showRing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    // Squash on the way in, overshoot, then settle — the dip is what makes it
    // read as a press rather than a plain grow.
    _pop = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.78)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.78, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 56,
      ),
    ]).animate(_controller);

    _ringScale = Tween<double>(begin: 0.35, end: 1.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );
    _ringFade = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.65)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    final wasFavorite = ref.read(userDataProvider).isFavorite(
          widget.song.filename,
        );

    HapticFeedback.mediumImpact();
    // No snackbar: the heart filling in already says what happened.
    songActionToggleFavorite(
      context,
      ref,
      widget.song.filename,
      widget.song.title,
      showFeedback: false,
    );

    // Both directions get the pop; only favouriting gets the ring.
    _showRing = !wasFavorite;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = ref.watch(
      userDataProvider.select((data) => data.isFavorite(widget.song.filename)),
    );

    return InkResponse(
      radius: 28,
      onTap: _toggle,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showHeartContextMenu(
          context: context,
          ref: ref,
          songFilename: widget.song.filename,
          songTitle: widget.song.title,
        );
      },
      child: SizedBox(
        width: 48,
        height: 48,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (_showRing && _controller.isAnimating && _ringFade.value > 0)
                  Transform.scale(
                    scale: _ringScale.value,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              widget.accent.withValues(alpha: _ringFade.value),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                Transform.scale(scale: _pop.value, child: child),
              ],
            );
          },
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 28,
            color: isFavorite
                ? widget.accent
                : Colors.white.withValues(alpha: PlayerTokens.aSecondary),
          ),
        ),
      ),
    );
  }
}

/// The artwork, or the video surface when the track has video and video mode is
/// on. The toggle lives outside it as [_VideoModeToggle], so the pane can hand
/// this the whole leftover box.
///
/// Artwork is square, as it always was. Video is not: it lays out at its own
/// aspect ratio inside the box, so a phone recording stays portrait and a music
/// video stays wide instead of both being letterboxed into the artwork's square.
class _CoverStage extends ConsumerWidget {
  final Song song;
  final Color accent;

  /// The artwork's side. Also what the video surface falls back to before it
  /// knows its own dimensions.
  final double size;

  /// The whole box the stage may use. Only video spreads into it.
  final double boxWidth;
  final double boxHeight;

  final PlayerCoverSizingMode coverSizing;
  final AudioPlayerManager audioManager;
  final PlayerMotionController motion;
  final GlobalKey coverKey;
  final ValueListenable<bool> paneVisible;

  const _CoverStage({
    required this.song,
    required this.accent,
    required this.size,
    required this.boxWidth,
    required this.boxHeight,
    required this.coverSizing,
    required this.audioManager,
    required this.motion,
    required this.coverKey,
    required this.paneVisible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beatReactive =
        ref.watch(settingsProvider.select((s) => s.beatReactiveCoverEnabled));

    return ValueListenableBuilder<PlaybackMediaMode>(
      valueListenable: audioManager.effectiveMediaModeNotifier,
      builder: (context, mode, _) {
        final isVideo = mode == PlaybackMediaMode.video;

        return SizedBox(
          width: boxWidth,
          height: boxHeight,
          // Centred outside the switcher, so each branch is free to size itself
          // — which is the whole point for video — and so the switcher still
          // sees two differently-typed children and crossfades between them.
          child: Center(
            child: AnimatedSwitcher(
              duration: PlayerTokens.dBase,
              switchInCurve: PlayerTokens.cStandard,
              child: isVideo
                  ? _VideoSurface(
                      key: ValueKey('video_${song.filename}'),
                      song: song,
                      audioManager: audioManager,
                      paneVisible: paneVisible,
                      placeholderSize: size,
                    )
                  : SizedBox(
                      width: size,
                      height: size,
                      child: _buildCover(context, beatReactive),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCover(BuildContext context, bool beatReactive) {
    // Tag must match NowPlayingBar's so the artwork flies between the mini bar
    // and this pane.
    //
    // The pulse wraps the artwork *inside* the Hero, never the Hero itself:
    // transforming the Hero would fight the flight animation between the mini
    // bar and this pane.
    return Hero(
      tag: PlayerTokens.coverHeroTag(song.filename),
      child: BeatReactiveCover(
        controller: motion,
        enabled: beatReactive,
        child: Container(
          // The shell's glow layer reads this box's on-screen rect every frame.
          // It sits inside the beat transform on purpose, so the glow tracks the
          // pulse — and the page swipe — without being told about either.
          key: coverKey,
          decoration: BoxDecoration(
            borderRadius: PlayerTokens.brLg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: PlayerTokens.brLg,
            child: AlbumArtImage(
              url: song.coverUrl ?? '',
              filename: song.filename,
              width: size,
              height: size,
              // autoFit crops to a square; sourceAspect keeps the original ratio.
              fit: coverSizing == PlayerCoverSizingMode.autoFit
                  ? BoxFit.cover
                  : BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// Switches the cover between artwork and video. Watches the media mode itself
/// so it can sit beside [_CoverStage] rather than inside it.
class _VideoModeToggle extends StatelessWidget {
  final Color accent;
  final AudioPlayerManager audioManager;

  const _VideoModeToggle({required this.accent, required this.audioManager});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackMediaMode>(
      valueListenable: audioManager.effectiveMediaModeNotifier,
      builder: (context, mode, _) {
        final isVideo = mode == PlaybackMediaMode.video;

        return TextButton.icon(
          onPressed: () {
            HapticFeedback.selectionClick();
            audioManager.setPreferredMediaMode(
              isVideo ? PlaybackMediaMode.audio : PlaybackMediaMode.video,
            );
          },
          icon: Icon(
            isVideo ? Icons.album_rounded : Icons.movie_outlined,
            size: 18,
          ),
          label: Text(isVideo ? 'Show artwork' : 'Show video'),
          style: TextButton.styleFrom(
            foregroundColor: isVideo ? accent : Colors.white70,
            padding: const EdgeInsets.symmetric(
              horizontal: PlayerTokens.s4,
              vertical: PlayerTokens.s2,
            ),
          ),
        );
      },
    );
  }
}

/// Muted video synced to the audio player.
///
/// just_audio stays the single source of audio truth — the video is always
/// silent and is corrected toward the audio clock, never the other way round.
///
/// Decoding video is the most expensive thing this app ever does, so the surface
/// only runs when someone can actually see it: not while the app is backgrounded
/// (the audio keeps going through just_audio_background regardless), and not
/// while the pane has been swiped away. Correction timing lives in
/// [resolveVideoSync] rather than here.
class _VideoSurface extends StatefulWidget {
  final Song song;
  final AudioPlayerManager audioManager;

  /// Whether this pane is the one on screen. Owned by the shell, which is where
  /// the pane ordering lives.
  final ValueListenable<bool> paneVisible;

  /// Fallback square for the placeholder and error states, which have no video
  /// dimensions to lay out against yet.
  final double placeholderSize;

  const _VideoSurface({
    super.key,
    required this.song,
    required this.audioManager,
    required this.paneVisible,
    required this.placeholderSize,
  });

  @override
  State<_VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<_VideoSurface>
    with WidgetsBindingObserver {
  /// Sync is checked on a timer rather than off `positionStream`: that stream
  /// emits every 200ms, while the video's own position only refreshes from a
  /// 100ms platform poll, so comparing them any faster than this mostly measures
  /// the gap between two clocks rather than any real drift.
  static const Duration _syncInterval = Duration(seconds: 1);

  VideoPlayerController? _controller;
  Timer? _syncTimer;
  StreamSubscription<PlayerState>? _stateSub;
  bool _initialized = false;
  Object? _error;

  /// Read once after initialize, never from a listener: the controller notifies
  /// on every 100ms position poll, so rebuilding off it would rebuild the
  /// subtree ten times a second for nothing.
  double _aspectRatio = 1;

  bool _appResumed = true;
  bool _visible = true;
  bool _seeking = false;
  final Stopwatch _sinceLastSeek = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _visible = widget.paneVisible.value;
    widget.paneVisible.addListener(_onPaneVisibilityChanged);
    _setUp();
  }

  @override
  void didUpdateWidget(_VideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paneVisible != widget.paneVisible) {
      oldWidget.paneVisible.removeListener(_onPaneVisibilityChanged);
      widget.paneVisible.addListener(_onPaneVisibilityChanged);
    }
    if (oldWidget.song.filename != widget.song.filename) {
      _tearDown();
      _setUp();
    }
  }

  @override
  void dispose() {
    widget.paneVisible.removeListener(_onPaneVisibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tearDown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    // Coming back, the audio has moved on without the video, so a plain resume
    // would start from wherever it was paused. Resync before playing.
    _applyPlayState(resync: resumed);
  }

  void _onPaneVisibilityChanged() {
    final visible = widget.paneVisible.value;
    if (visible == _visible) return;
    _visible = visible;
    // Same as coming back from the background: the audio ran on while the video
    // sat paused, so it has to be put back in place before it resumes.
    _applyPlayState(resync: visible);
  }

  String? _resolveVideoPath() {
    // The manager writes a directly playable path into the MediaItem — on iOS
    // that may be a transcoded proxy rather than the original file.
    final tag = widget.audioManager.player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      final path = tag.extras?['videoPath'];
      if (path is String && path.isNotEmpty) return path;
    }
    return widget.song.hasVideo ? widget.song.url : null;
  }

  Future<void> _setUp() async {
    final path = _resolveVideoPath();
    if (path == null) return;

    final controller = VideoPlayerController.file(
      File(path),
      // Without this the video's own ExoPlayer requests audio focus the moment
      // it plays, and the system duly tells just_audio it has lost focus — the
      // music ducks or stops. Muting the video does not prevent that; only
      // declining to handle focus does.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setVolume(0);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }

    if (!mounted || _controller != controller) {
      await controller.dispose();
      return;
    }

    final player = widget.audioManager.player;
    await controller.seekTo(player.position);
    _sinceLastSeek
      ..reset()
      ..start();

    _stateSub = player.playerStateStream.listen((_) {
      if (_controller != controller) return;
      _applyPlayState();
    });

    _syncTimer = Timer.periodic(_syncInterval, (_) => _syncToAudio());

    await _applyPlayState();

    if (mounted) {
      setState(() {
        _aspectRatio = videoDisplayAspectRatio(
          controller.value.aspectRatio,
          controller.value.rotationCorrection,
        );
        _initialized = true;
      });
    }
  }

  /// The one place that decides whether the video is running.
  ///
  /// Three things can veto playback — the audio being paused, the app being
  /// backgrounded, the pane being swiped away — and routing all of them through
  /// here is what stops them from contradicting each other.
  Future<void> _applyPlayState({bool resync = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final player = widget.audioManager.player;
    final shouldPlay = player.playing && _appResumed && _visible;

    if (!shouldPlay) {
      if (controller.value.isPlaying) await controller.pause();
      return;
    }

    if (resync) await _seekTo(player.position);
    if (_controller != controller) return;
    if (!controller.value.isPlaying) await controller.play();
  }

  Future<void> _syncToAudio() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_appResumed || !_visible) return;

    final player = widget.audioManager.player;
    final action = resolveVideoSync(
      audioPosition: player.position,
      videoPosition: controller.value.position,
      audioPlaying: player.playing,
      videoBuffering: controller.value.isBuffering,
      seekInFlight: _seeking,
      msSinceLastSeek: _sinceLastSeek.isRunning
          ? _sinceLastSeek.elapsedMilliseconds.toDouble()
          : double.infinity,
    );
    if (action == VideoSyncAction.none) return;

    await _seekTo(player.position);
  }

  /// Seeks with a reentrancy guard: an exact seek can take a while on a slow
  /// decoder, and stacking them up is how the old sync loop stalled playback.
  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (controller == null || _seeking) return;

    _seeking = true;
    try {
      await controller.seekTo(position);
    } catch (_) {
      // A seek that lands after disposal is not worth surfacing.
    } finally {
      _seeking = false;
      _sinceLastSeek
        ..reset()
        ..start();
    }
  }

  void _tearDown() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _stateSub?.cancel();
    _stateSub = null;
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    _seeking = false;
    _sinceLastSeek.stop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_error != null || (controller == null && _resolveVideoPath() == null)) {
      return _buildPlaceholder(const Icon(Icons.videocam_off_rounded));
    }

    if (!_initialized || controller == null) {
      return _buildPlaceholder(
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    // Sized to the video rather than boxed into the artwork's square, so there
    // is nothing to letterbox — the shell's backdrop shows through around it.
    // The repaint boundary keeps the beat-reactive chrome painting beside this
    // from pulling the video texture into its repaints every frame.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: PlayerTokens.brLg,
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  /// Square, because until the controller reports its dimensions there is no
  /// video shape to lay out against and a guess would only make things jump.
  Widget _buildPlaceholder(Widget child) {
    return SizedBox(
      width: widget.placeholderSize,
      height: widget.placeholderSize,
      child: ClipRRect(
        borderRadius: PlayerTokens.brLg,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(child: child),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio_player_manager.dart';
import '../../services/power_state_service.dart';
import '../../services/screen_wake_lock_service.dart';
import '../../theme/app_theme.dart';
import '../components/player_segmented_pill.dart';
import '../components/pressable.dart';
import '../components/song_actions.dart';
import '../tokens/player_tokens.dart';
import '../widgets/basic_progress_bar.dart';
import '../widgets/beat_cover_glow.dart';
import '../widgets/beat_particle_field.dart';
import '../widgets/blurred_background.dart';
import '../widgets/clickable_artist_text.dart';
import '../widgets/player_motion.dart';
import '../widgets/smooth_color_builder.dart';
import '../widgets/song_options_menu.dart';
import '../widgets/waveform_progress_bar.dart';
import 'player/lyrics_pane.dart';
import 'player/now_playing_pane.dart';
import 'player/queue_pane.dart';

enum PlayerPane { lyrics, player, queue }

/// The unified player: Lyrics ◀ Player ▶ Queue.
///
/// This shell owns *all* the chrome — the cover backdrop, the header, the
/// segmented pill and the transport dock. The three panes render content only.
/// That split is deliberate: the panes cannot drift apart stylistically because
/// they no longer own the pieces that would let them.
class UnifiedPlayerScreen extends ConsumerStatefulWidget {
  final PlayerPane initialPane;

  /// Opens the Queue pane directly on its History segment.
  final bool queueShowsHistory;

  const UnifiedPlayerScreen({
    super.key,
    this.initialPane = PlayerPane.player,
    this.queueShowsHistory = false,
  });

  @override
  ConsumerState<UnifiedPlayerScreen> createState() =>
      _UnifiedPlayerScreenState();
}

class _UnifiedPlayerScreenState extends ConsumerState<UnifiedPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _wakeLockReason = 'unified_player_lyrics';

  late final PageController _pageController;

  /// Drives every beat-reactive element on this screen. Owned by the shell so
  /// the cover and the particle field share one ticker and one playhead clock
  /// rather than each running their own.
  late final PlayerMotionController _motion;

  /// Continuous page position, so the pill thumb tracks the swipe rather than
  /// snapping once the page settles.
  final ValueNotifier<double> _pagePosition = ValueNotifier(0);

  /// Whether the Now Playing pane is the one being looked at. The panes are kept
  /// alive across swipes, which is right for state but wrong for a video
  /// decoder — it would keep running behind the Lyrics or Queue pane.
  final ValueNotifier<bool> _nowPlayingVisible = ValueNotifier(false);
  final ValueNotifier<bool> _lyricsVisible = ValueNotifier(false);

  /// Let the glow layer locate the artwork inside the pane, and convert it into
  /// the shell's coordinates. The glow is painted up here so it can spill past
  /// the pane, which clips.
  final GlobalKey _coverKey = GlobalKey(debugLabel: 'player cover');
  final GlobalKey _shellKey = GlobalKey(debugLabel: 'player shell');

  late int _pane;
  bool _wakeLockHeld = false;
  bool _appActive = true;
  double _dismissDrag = 0;

  /// Mirrors the OS "remove animations" accessibility switch. When it is on,
  /// every self-driven animation on this screen stops — the beat motion, the
  /// mote field and the backdrop spin — regardless of what the appearance
  /// settings say. The user has already told the system what they want.
  bool _reduceMotion = false;

  /// Guards against a slow analysis landing after the user has skipped on.
  String? _beatMapFilename;
  int _beatMapToken = 0;

  @override
  void initState() {
    super.initState();
    _pane = widget.initialPane.index;
    _pagePosition.value = _pane.toDouble();
    _nowPlayingVisible.value = _isNowPlayingVisible(_pagePosition.value);
    _lyricsVisible.value = _isLyricsVisible(_pagePosition.value);
    _pageController = PageController(initialPage: _pane);
    _pageController.addListener(_onPageScroll);

    WidgetsBinding.instance.addObserver(this);

    final manager = ref.read(audioPlayerManagerProvider);
    _motion = PlayerMotionController(player: manager.player)..attach(this);
    manager.currentSongNotifier.addListener(_onSongChanged);
    PowerStateService.instance.powerSave.addListener(_syncMotionSettings);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncWakeLock();
      _syncMotionSettings();
      _onSongChanged();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref
        .read(audioPlayerManagerProvider)
        .currentSongNotifier
        .removeListener(_onSongChanged);
    PowerStateService.instance.powerSave.removeListener(_syncMotionSettings);
    _motion.dispose();
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pagePosition.dispose();
    _nowPlayingVisible.dispose();
    _lyricsVisible.dispose();
    _releaseWakeLock();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    // Deferred: this runs inside the build phase, and the motion setters notify
    // the painters listening to them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMotionSettings();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Backgrounded means nobody is watching: stop every visual and lyric
    // listener rather than animating a screen that is not on.
    _appActive = state == AppLifecycleState.resumed;
    _motion.appActive = _appActive;
    if (_appActive) {
      _nowPlayingVisible.value = _isNowPlayingVisible(_pagePosition.value);
      _lyricsVisible.value = _isLyricsVisible(_pagePosition.value);
    } else {
      _nowPlayingVisible.value = false;
      _lyricsVisible.value = false;
    }
  }

  /// Loads the beat map for whatever is now playing.
  ///
  /// Reads the cache first so an already-analysed track locks on instantly;
  /// only falls through to analysis when there is nothing cached, during which
  /// the motion layer breathes rather than sitting still.
  Future<void> _onSongChanged() async {
    final song = ref.read(audioPlayerManagerProvider).currentSongNotifier.value;
    if (song == null) {
      _beatMapFilename = null;
      _motion.beatMap = null;
      return;
    }
    if (song.filename == _beatMapFilename) return;

    _beatMapFilename = song.filename;
    final token = ++_beatMapToken;
    _motion.beatMap = null;

    final service = ref.read(beatAnalysisServiceProvider);
    final cached = await service.readCached(song.filename);
    if (!mounted || token != _beatMapToken) return;
    if (cached != null) {
      _motion.beatMap = cached;
      return;
    }

    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation != null && !animation.isCompleted) {
      final completer = Completer<void>();
      AnimationStatusListener? listener;
      listener = (status) {
        if (status == AnimationStatus.completed) {
          animation.removeStatusListener(listener!);
          if (!completer.isCompleted) completer.complete();
        }
      };
      animation.addStatusListener(listener);
      await completer.future;
      if (!mounted || token != _beatMapToken) return;
    }

    final analyzed = await service.analyze(song.filename, song.url);
    if (!mounted || token != _beatMapToken) return;
    _motion.beatMap = analyzed;
  }

  void _syncMotionSettings() {
    final settings = ref.read(settingsProvider);
    _motion
      ..powerSave = PowerStateService.instance.powerSave.value
      ..enabled = !_reduceMotion &&
          (settings.beatReactiveCoverEnabled ||
              settings.beatReactiveParticlesEnabled)
      ..coverIntensity = settings.coverMotionIntensity
      ..particleIntensity = settings.particleMotionIntensity
      ..coverCustomIntensity = settings.coverMotionCustomIntensity
      ..particleCustomIntensity = settings.particleMotionCustomIntensity
      ..latencyMs = settings.playerMotionLatencyMs;
  }

  /// Under a full page of slack, so a settled neighbouring pane always counts as
  /// hidden while an overscroll or a bounce does not.
  bool _isNowPlayingVisible(double page) =>
      (page - PlayerPane.player.index).abs() <= 0.6;

  bool _isLyricsVisible(double page) =>
      (page - PlayerPane.lyrics.index).abs() <= 0.6;

  void _onPageScroll() {
    final page = _pageController.page;
    if (page == null) return;
    _pagePosition.value = page;
    _nowPlayingVisible.value = _appActive && _isNowPlayingVisible(page);
    _lyricsVisible.value = _appActive && _isLyricsVisible(page);

    // Deliberately no setState: nothing in build() depends on _pane, and
    // rebuilding the shell mid-swipe would re-render the backdrop and dock,
    // which is exactly the flicker the pinned-chrome layout exists to avoid.
    final settled = page.round();
    if (settled != _pane) {
      _pane = settled;
      _syncWakeLock();
    }
  }

  /// Holds the screen awake only while the Lyrics pane is showing and the
  /// setting is on. The service is reason-counted, so acquire/release must stay
  /// balanced — [_wakeLockHeld] is what guarantees that.
  void _syncWakeLock() {
    final wanted = _pane == PlayerPane.lyrics.index &&
        ref.read(settingsProvider).keepScreenAwakeOnLyrics;

    if (wanted && !_wakeLockHeld) {
      _wakeLockHeld = true;
      ScreenWakeLockService.instance.acquire(_wakeLockReason);
    } else if (!wanted && _wakeLockHeld) {
      _releaseWakeLock();
    }
  }

  void _releaseWakeLock() {
    if (!_wakeLockHeld) return;
    _wakeLockHeld = false;
    ScreenWakeLockService.instance.release(_wakeLockReason);
  }

  void _goToPane(int index) {
    _pageController.animateToPage(
      index,
      duration: PlayerTokens.dBase,
      curve: PlayerTokens.cEmphasized,
    );
  }

  void _onDismissDragUpdate(DragUpdateDetails details) {
    _dismissDrag += details.delta.dy;
  }

  void _onDismissDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dismissDrag > 90 || velocity > 700) {
      Navigator.of(context).maybePop();
    }
    _dismissDrag = 0;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    // Lifted once here and passed down, so every pane shares one legible accent
    // rather than each deciding how to cope with a near-black cover palette.
    final accent =
        themeState.extractedColor ?? Theme.of(context).colorScheme.primary;

    ref.listen(
      settingsProvider.select((s) => s.keepScreenAwakeOnLyrics),
      (_, __) => _syncWakeLock(),
    );

    ref.listen(
      settingsProvider.select(
        (s) => (
          s.beatReactiveCoverEnabled,
          s.beatReactiveParticlesEnabled,
          s.coverMotionIntensity,
          s.particleMotionIntensity,
          s.coverMotionCustomIntensity,
          s.particleMotionCustomIntensity,
          s.playerMotionLatencyMs,
        ),
      ),
      (_, __) => _syncMotionSettings(),
    );

    return Theme(
      data: AppTheme.getPlayerTheme(themeState, accent),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          body: ValueListenableBuilder<Song?>(
            valueListenable:
                ref.watch(audioPlayerManagerProvider).currentSongNotifier,
            builder: (context, song, _) {
              if (song == null) return _buildEmptyState(context);
              return _buildBody(context, song, accent);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
            ),
            const SizedBox(height: PlayerTokens.s3),
            Text('Nothing playing', style: PlayerTokens.paneTitle(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Song song, Color accent) {
    final showParticles = !_reduceMotion &&
        ref.watch(
            settingsProvider.select((s) => s.beatReactiveParticlesEnabled));
    final showGlow = !_reduceMotion &&
        ref.watch(settingsProvider.select((s) => s.beatReactiveCoverEnabled));

    return Stack(
      key: _shellKey,
      children: [
        // Backdrop — built outside the PageView so swiping never re-blurs it.
        Positioned.fill(
          child: _PlayerBackdrop(
            song: song,
            accent: accent,
            allowSpin: !_reduceMotion,
          ),
        ),
        // Above the backdrop but below the content column, so the glow bleeds
        // across the whole screen while the pill, title and dock stay crisp on
        // top of it.
        if (showGlow)
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: _nowPlayingVisible,
              child: BeatCoverGlow(
                controller: _motion,
                coverKey: _coverKey,
                shellKey: _shellKey,
                accent: accent,
              ),
              builder: (context, visible, child) {
                if (!visible || child == null) return const SizedBox.shrink();
                return child;
              },
            ),
          ),
        // Chrome, so the field carries across all three panes rather than
        // living inside one of them.
        if (showParticles)
          Positioned.fill(
            child: BeatParticleField(controller: _motion, accent: accent),
          ),
        SafeArea(
          child: Column(
            children: [
              _buildHeader(context, song),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayerTokens.s5,
                  vertical: PlayerTokens.s2,
                ),
                child: PlayerSegmentedPill(
                  labels: const ['Lyrics', 'Player', 'Queue'],
                  position: _pagePosition,
                  onSelected: _goToPane,
                  accent: accent,
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    LyricsPane(
                      song: song,
                      accent: accent,
                      paneVisible: _lyricsVisible,
                    ),
                    NowPlayingPane(
                      song: song,
                      accent: accent,
                      motion: _motion,
                      coverKey: _coverKey,
                      paneVisible: _nowPlayingVisible,
                    ),
                    QueuePane(
                      accent: accent,
                      initialShowHistory: widget.queueShowsHistory,
                    ),
                  ],
                ),
              ),
              _TransportDock(song: song, accent: accent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Song song) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDismissDragUpdate,
      onVerticalDragEnd: _onDismissDragEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PlayerTokens.s5,
          PlayerTokens.s2,
          PlayerTokens.s3,
          PlayerTokens.s1,
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: PlayerTokens.s3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: PlayerTokens.brPill,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Close',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: PlayerTokens.trackTitle(context),
                      ),
                      ClickableArtistText(
                        artist: song.artist,
                        textAlign: TextAlign.center,
                        style: PlayerTokens.trackSubtitle(context),
                        onArtistTap: (artistName) => songActionGoToArtistByName(
                            context, ref, artistName),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  color: Colors.white,
                  tooltip: 'Song options',
                  onPressed: () => showSongOptionsMenu(
                    context,
                    ref,
                    song.filename,
                    song.title,
                    song: song,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover-derived backdrop shared by all three panes. The accent scrim is driven
/// through [SmoothColorBuilder] so palette changes between tracks crossfade
/// instead of snapping.
class _PlayerBackdrop extends ConsumerWidget {
  final Song song;
  final Color accent;

  /// False when the OS has asked for less motion. The spin is decoration; it is
  /// the first thing to go.
  final bool allowSpin;

  const _PlayerBackdrop({
    required this.song,
    required this.accent,
    required this.allowSpin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SmoothColorBuilder(
      targetColor: accent,
      builder: (context, color) {
        final gradientColors = [
          Color.alphaBlend(
            color.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.62),
          ),
          Colors.black.withValues(alpha: 0.92),
        ];
        // The spin follows playback rather than running forever. Rotating and
        // scaling a full-screen image repaints the whole backdrop every frame,
        // and a paused player left it doing that indefinitely with nothing to
        // be in time with.
        return ValueListenableBuilder<bool>(
          valueListenable:
              ref.watch(audioPlayerManagerProvider).playingNotifier,
          builder: (context, playing, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                BlurredBackground(
                  url: song.coverUrl ?? '',
                  filename: song.filename,
                  slowSpin: playing && allowSpin,
                  gradientColors: gradientColors,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Pinned transport: seek bar plus controls. Lives in the shell so it stays
/// put — and keeps working — no matter which pane is showing.
class _TransportDock extends ConsumerWidget {
  final Song song;
  final Color accent;

  const _TransportDock({required this.song, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final player = audioManager.player;
    final showWaveform =
        ref.watch(settingsProvider.select((s) => s.showWaveform));

    // Deliberately sits directly on the backdrop — no card, no border. Nesting
    // the controls inside another surface just stacks boxes on boxes.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s5,
        PlayerTokens.s2,
        PlayerTokens.s5,
        PlayerTokens.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The seek bar follows the playhead several times a second, and it
          // sits in the same layer as the backdrop, the glow and the mote
          // field. Its own boundary keeps those out of its repaints.
          RepaintBoundary(
            child: StreamBuilder<Duration?>(
              stream: player.durationStream,
              initialData: player.duration,
              builder: (context, snapshot) {
                final total = snapshot.data ?? song.duration ?? Duration.zero;

                if (showWaveform) {
                  return WaveformProgressBar(
                    key: ValueKey('waveform_${song.filename}'),
                    filename: song.filename,
                    path: song.url,
                    progress: player.position,
                    total: total,
                    positionStream: player.positionStream,
                    onSeek: player.seek,
                  );
                }

                return BasicProgressBar(
                  key: ValueKey('basic_${song.filename}'),
                  player: player,
                  total: total,
                  onSeek: player.seek,
                );
              },
            ),
          ),
          const SizedBox(height: PlayerTokens.s1),
          _buildControls(context, ref, audioManager, player),
        ],
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    WidgetRef ref,
    AudioPlayerManager audioManager,
    AudioPlayer player,
  ) {
    // Both streams matter: the sequence drives hasPrevious/hasNext, and loop mode
    // feeds into them too (repeat-all wraps around, so the ends stay enabled).
    return StreamBuilder<LoopMode>(
      stream: player.loopModeStream,
      initialData: player.loopMode,
      builder: (context, loopSnapshot) {
        return StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, _) => _buildControlRow(
            context,
            audioManager,
            player,
            loopSnapshot.data ?? LoopMode.off,
          ),
        );
      },
    );
  }

  Widget _buildControlRow(
    BuildContext context,
    AudioPlayerManager audioManager,
    AudioPlayer player,
    LoopMode loopMode,
  ) {
    final canSkipPrevious = player.hasPrevious;
    final canSkipNext = player.hasNext;
    final disabled = Colors.white.withValues(alpha: PlayerTokens.aTertiary);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: switch (loopMode) {
            LoopMode.off => 'Repeat off',
            LoopMode.all => 'Repeat all',
            LoopMode.one => 'Repeat one',
          },
          icon: Icon(
            loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: loopMode == LoopMode.off ? disabled : accent,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            player.setLoopMode(switch (loopMode) {
              LoopMode.off => LoopMode.all,
              LoopMode.all => LoopMode.one,
              LoopMode.one => LoopMode.off,
            });
          },
        ),
        Pressable(
          onTap: canSkipPrevious ? player.seekToPrevious : null,
          child: Padding(
            padding: const EdgeInsets.all(PlayerTokens.s3),
            child: Icon(
              Icons.skip_previous_rounded,
              size: 34,
              color: canSkipPrevious ? Colors.white : disabled,
            ),
          ),
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          initialData: player.playerState,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final playing = state?.playing ?? false;
            final buffering =
                state?.processingState == ProcessingState.buffering;

            return Pressable(
              onTap: audioManager.togglePlayPause,
              pressedScale: 0.9,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: buffering
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: PlayerTokens.onAccent(accent),
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                        color: PlayerTokens.onAccent(accent),
                      ),
              ),
            );
          },
        ),
        Pressable(
          onTap: canSkipNext ? player.seekToNext : null,
          child: Padding(
            padding: const EdgeInsets.all(PlayerTokens.s3),
            child: Icon(
              Icons.skip_next_rounded,
              size: 34,
              color: canSkipNext ? Colors.white : disabled,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Share',
          icon: Icon(Icons.ios_share_rounded, color: disabled),
          onPressed: () {
            HapticFeedback.selectionClick();
            songActionShare(song);
          },
        ),
      ],
    );
  }
}

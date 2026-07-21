import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import '../../providers/audio_energy_provider.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio_player_manager.dart';
import '../../services/screen_wake_lock_service.dart';
import '../../theme/app_theme.dart';
import '../components/player_segmented_pill.dart';
import '../tokens/player_tokens.dart';
import '../widgets/basic_progress_bar.dart';
import '../widgets/blurred_background.dart';
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

class _UnifiedPlayerScreenState extends ConsumerState<UnifiedPlayerScreen> {
  static const String _wakeLockReason = 'unified_player_lyrics';

  late final PageController _pageController;

  /// Continuous page position, so the pill thumb tracks the swipe rather than
  /// snapping once the page settles.
  final ValueNotifier<double> _pagePosition = ValueNotifier(0);

  late int _pane;
  bool _wakeLockHeld = false;
  double _dismissDrag = 0;

  /// Captured up front: dispose() runs after ref access is no longer allowed.
  PlayerScreenActiveNotifier? _activeNotifier;

  @override
  void initState() {
    super.initState();
    _pane = widget.initialPane.index;
    _pagePosition.value = _pane.toDouble();
    _pageController = PageController(initialPage: _pane);
    _pageController.addListener(_onPageScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeNotifier = ref.read(playerScreenActiveProvider.notifier);
      _activeNotifier!.setActive(true);
      _syncWakeLock();
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pagePosition.dispose();
    _releaseWakeLock();
    _activeNotifier?.setActive(false);
    super.dispose();
  }

  void _onPageScroll() {
    final page = _pageController.page;
    if (page == null) return;
    _pagePosition.value = page;

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
    final accent = PlayerTokens.vibrant(
      themeState.extractedColor ?? Theme.of(context).colorScheme.primary,
    );

    ref.listen(
      settingsProvider.select((s) => s.keepScreenAwakeOnLyrics),
      (_, __) => _syncWakeLock(),
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
    return Stack(
      children: [
        // Backdrop — built outside the PageView so swiping never re-blurs it.
        Positioned.fill(
          child: _PlayerBackdrop(song: song, accent: accent),
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
                    LyricsPane(song: song, accent: accent),
                    NowPlayingPane(song: song, accent: accent),
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
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: PlayerTokens.trackSubtitle(context),
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
class _PlayerBackdrop extends StatelessWidget {
  final Song song;
  final Color accent;

  const _PlayerBackdrop({required this.song, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SmoothColorBuilder(
      targetColor: accent,
      builder: (context, color) {
        return Stack(
          fit: StackFit.expand,
          children: [
            BlurredBackground(
              url: song.coverUrl ?? '',
              filename: song.filename,
              slowSpin: true,
              gradientColors: [
                Color.alphaBlend(
                  color.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.62),
                ),
                Colors.black.withValues(alpha: 0.92),
              ],
            ),
          ],
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
        PlayerTokens.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration?>(
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: audioManager.shuffleNotifier,
          builder: (context, shuffleOn, _) => IconButton(
            tooltip: 'Shuffle',
            icon: Icon(
              Icons.shuffle_rounded,
              color: shuffleOn
                  ? accent
                  : Colors.white.withValues(alpha: PlayerTokens.aTertiary),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              audioManager.toggleShuffle();
            },
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 34,
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
          onPressed: player.hasPrevious ? player.seekToPrevious : null,
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          initialData: player.playerState,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final playing = state?.playing ?? false;
            final buffering =
                state?.processingState == ProcessingState.buffering;

            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                audioManager.togglePlayPause();
              },
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
        IconButton(
          tooltip: 'Next',
          iconSize: 34,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
          onPressed: player.hasNext ? player.seekToNext : null,
        ),
        StreamBuilder<LoopMode>(
          stream: player.loopModeStream,
          initialData: player.loopMode,
          builder: (context, snapshot) {
            final mode = snapshot.data ?? LoopMode.off;
            return IconButton(
              tooltip: switch (mode) {
                LoopMode.off => 'Repeat off',
                LoopMode.all => 'Repeat all',
                LoopMode.one => 'Repeat one',
              },
              icon: Icon(
                mode == LoopMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: mode == LoopMode.off
                    ? Colors.white.withValues(alpha: PlayerTokens.aTertiary)
                    : accent,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                player.setLoopMode(switch (mode) {
                  LoopMode.off => LoopMode.all,
                  LoopMode.all => LoopMode.one,
                  LoopMode.one => LoopMode.off,
                });
              },
            );
          },
        ),
      ],
    );
  }
}

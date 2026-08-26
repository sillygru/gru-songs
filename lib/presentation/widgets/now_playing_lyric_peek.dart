import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/database_service.dart';
import '../models/lyrics_gap_loader_state.dart';
import '../tokens/player_tokens.dart';
import 'lyrics_gap_loader.dart';

/// The current synced-lyric line, shown under the title on the now-playing
/// pane — the Spotify-style peek. It only appears when the track actually has
/// time-synced lyrics; unsynced or missing lyrics render nothing at all, so the
/// pane keeps its shape.
///
/// This reuses the same lyrics source and active-line logic as [LyricsPane]
/// (the repository's disk-cached `getLyrics` and the "last synced line whose
/// timestamp has passed" rule), so the peek and the full lyrics pane can never
/// disagree about which line is current.
///
/// When translated lyrics are available, the peek shows the translated text
/// (respecting the user's translation mode). Text that overflows the available
/// width scrolls horizontally (marquee) so nothing is clipped.
///
/// During long instrumental gaps it swaps to the same three-dot loader the
/// lyrics pane uses, scaled to the peek's single-line height.
class NowPlayingLyricPeek extends ConsumerStatefulWidget {
  final Song song;
  final Color accent;
  final ValueListenable<bool> paneVisible;

  const NowPlayingLyricPeek({
    super.key,
    required this.song,
    required this.accent,
    required this.paneVisible,
  });

  @override
  ConsumerState<NowPlayingLyricPeek> createState() =>
      _NowPlayingLyricPeekState();
}

class _NowPlayingLyricPeekState extends ConsumerState<NowPlayingLyricPeek> {
  /// Same thresholds as [LyricsPane] so the peek and full lyrics agree on when
  /// a silence counts as a real gap.
  static const Duration _gapLoaderDelay = Duration(seconds: 5);
  static const Duration _minimumGapLoaderWindow = Duration(seconds: 3);
  static const Duration _gapCollapseHold = PlayerTokens.dSlow;

  List<LyricLine> _lines = const [];
  List<LyricLine?> _translatedLines = const [];
  bool _hasSynced = false;
  String? _loadedFilename;

  /// The line currently being sung.
  ///
  /// Resolved from a playhead subscription rather than a `StreamBuilder`: the
  /// stream ticks about five times a second and the line changes every few
  /// seconds, so building off the stream directly laid out the text — and ran
  /// the switcher's whole subtree — dozens of times per line for one visible
  /// change.
  final ValueNotifier<String> _line = ValueNotifier('');

  /// Whether the compact gap loader is occupying the peek instead of text.
  final ValueNotifier<bool> _gapVisible = ValueNotifier(false);

  /// Gap fill progress, scoped to the loader widget alone.
  final ValueNotifier<double> _gapProgress = ValueNotifier(0);

  Timer? _gapCollapseTimer;
  StreamSubscription<Duration>? _positionSub;
  bool _positionSubscriptionActive = false;

  @override
  void initState() {
    super.initState();
    widget.paneVisible.addListener(_syncPositionSubscription);
    _syncPositionSubscription();
    _load();
  }

  void _syncPositionSubscription() {
    final wanted = widget.paneVisible.value;
    if (wanted == _positionSubscriptionActive) return;
    _positionSubscriptionActive = wanted;

    if (!wanted) {
      _positionSub?.cancel();
      _positionSub = null;
      return;
    }

    _positionSub = ref
        .read(audioPlayerManagerProvider)
        .player
        .positionStream
        .listen(_onPosition);
    _onPosition(ref.read(audioPlayerManagerProvider).player.position);
  }

  @override
  void dispose() {
    _gapCollapseTimer?.cancel();
    widget.paneVisible.removeListener(_syncPositionSubscription);
    _positionSub?.cancel();
    _line.dispose();
    _gapVisible.dispose();
    _gapProgress.dispose();
    super.dispose();
  }

  void _onPosition(Duration position) {
    if (!_hasSynced) return;

    final gap = computeLyricsGapLoaderState(
      lyrics: _lines,
      position: position,
      delay: _gapLoaderDelay,
      minimumWindow: _minimumGapLoaderWindow,
    );

    if (gap.shouldShow) {
      _gapCollapseTimer?.cancel();
      _gapCollapseTimer = null;
      _gapVisible.value = true;
      _gapProgress.value = gap.progress;
      // Clear the lyric so the switcher does not flash old text under the dots.
      if (_line.value.isNotEmpty) _line.value = '';
      return;
    }

    if (_gapVisible.value && _gapCollapseTimer == null) {
      _gapProgress.value = 1;
      _gapCollapseTimer = Timer(_gapCollapseHold, () {
        if (!mounted) return;
        _gapVisible.value = false;
        _gapProgress.value = 0;
        _gapCollapseTimer = null;
        _onPosition(ref.read(audioPlayerManagerProvider).player.position);
      });
      return;
    }

    if (_gapVisible.value) return;

    final active = _activeIndexFor(position);
    final resolved = active >= 0 ? _resolveText(active) : '';
    if (resolved != _line.value) {
      _line.value = resolved;
    }
  }

  @override
  void didUpdateWidget(NowPlayingLyricPeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paneVisible != widget.paneVisible) {
      oldWidget.paneVisible.removeListener(_syncPositionSubscription);
      widget.paneVisible.addListener(_syncPositionSubscription);
      _syncPositionSubscription();
    }
    if (oldWidget.song.filename != widget.song.filename) _load();
  }

  /// Resolves what text to display for the active lyric line, considering
  /// translated lyrics and the user's translation mode.
  String _resolveText(int activeIndex) {
    if (activeIndex < 0 || activeIndex >= _lines.length) return '';

    final settings = ref.read(settingsProvider);
    final mode = settings.lyricsTranslationMode;
    final translated =
        _translatedLines.isNotEmpty && activeIndex < _translatedLines.length
            ? _translatedLines[activeIndex]
            : null;
    if (translated == null || translated.text.trim().isEmpty) {
      return _lines[activeIndex].text.trim();
    }

    // Both 'replace' and 'subtext' modes show the translated text in the peek
    // (the full pane shows subtext alongside the original; the peek is
    // constrained to one line so it shows the translation directly).
    if (mode == 'replace' || mode == 'subtext') {
      return translated.text.trim();
    }

    return _lines[activeIndex].text.trim();
  }

  Future<void> _load() async {
    final filename = widget.song.filename;
    _gapCollapseTimer?.cancel();
    _gapCollapseTimer = null;
    _loadedFilename = filename;
    _hasSynced = false;
    _lines = const [];
    _translatedLines = const [];
    _gapVisible.value = false;
    _gapProgress.value = 0;

    final content = await ref.read(songRepositoryProvider).getLyrics(
          widget.song,
        );
    if (!mounted || _loadedFilename != filename) return;

    final parsed = (content == null || content.trim().isEmpty)
        ? const <LyricLine>[]
        : LyricLine.parse(content);

    setState(() {
      _lines = parsed;
      _hasSynced = parsed.any((l) => l.isSynced);
    });

    // Load translated lyrics if available
    if (parsed.isNotEmpty) {
      final settings = ref.read(settingsProvider);
      final translatedContent =
          await DatabaseService.instance.getTranslatedLyrics(
        filename,
        settings.lyricsTargetLanguage,
        sourceContent: content,
      );

      if (!mounted || _loadedFilename != filename) return;

      if (translatedContent != null &&
          translatedContent != '[SAME_LANG]' &&
          translatedContent.trim().isNotEmpty) {
        final translatedParsed = LyricLine.alignTranslation(
          parsed,
          LyricLine.parse(translatedContent),
        );
        if (mounted) {
          setState(() {
            _translatedLines = translatedParsed;
          });
        }
      }
    }

    _line.value = '';
    _onPosition(ref.read(audioPlayerManagerProvider).player.position);
  }

  int _activeIndexFor(Duration position) {
    int idx = -1;
    for (int i = 0; i < _lines.length; i++) {
      if (!_lines[i].isSynced) continue;
      if (_lines[i].time <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    // Lyrics live in the audio file, not in provider state. Same signal the
    // lyrics pane uses so a freshly fetched track shows up without reopening.
    ref.listen(lyricsRevisionProvider, (_, __) => _load());

    if (!_hasSynced) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PlayerTokens.s5),
      child: SizedBox(
        height: 24,
        child: ListenableBuilder(
          listenable: Listenable.merge([_line, _gapVisible]),
          builder: (context, _) {
            final showingGap = _gapVisible.value;
            final text = _line.value;

            return AnimatedSwitcher(
              duration: PlayerTokens.dBase,
              switchInCurve: PlayerTokens.cStandard,
              switchOutCurve: PlayerTokens.cStandard,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.35),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: showingGap
                  ? ValueListenableBuilder<double>(
                      key: const ValueKey('lyric-peek-gap'),
                      valueListenable: _gapProgress,
                      builder: (context, progress, _) => LyricsGapLoader(
                        progress: progress,
                        accent: widget.accent,
                        compact: true,
                      ),
                    )
                  : text.isEmpty
                      ? const SizedBox.shrink(key: ValueKey('lyric-peek-empty'))
                      : _MarqueeText(
                          key: ValueKey(text),
                          text: text,
                          style: PlayerTokens.trackSubtitle(context).copyWith(
                            color: widget.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
            );
          },
        ),
      ),
    );
  }
}

/// A text widget that horizontally auto-scrolls (marquee) when the text
/// overflows its available width. It slowly scrolls to the end, pauses, then
/// scrolls back to the start — making long lines fully readable in the
/// constrained peek area.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  ScrollController? _controller;
  late AnimationController _animController;
  bool _overflows = false;
  double _scrollExtent = 0;

  // Durations for each phase of the marquee cycle, in milliseconds.
  static const int _scrollForwardMs = 3000;
  static const int _pauseEndMs = 2000;
  static const int _scrollBackMs = 2500;
  static const int _pauseStartMs = 1500;
  static const int _cycleMs =
      _scrollForwardMs + _pauseEndMs + _scrollBackMs + _pauseStartMs;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    );
    _animController.addListener(_tick);
    _animController.addStatusListener(_onLoop);
    _measure();
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _animController.reset();
      _controller?.dispose();
      _controller = null;
      _overflows = false;
      _scrollExtent = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _animController.removeListener(_tick);
    _animController.removeStatusListener(_onLoop);
    _animController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onLoop(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animController.forward(from: 0);
    }
  }

  void _measure() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null || !controller.hasClients) return;
      final viewport = controller.position.viewportDimension;
      final extent = controller.position.maxScrollExtent;
      if (extent > viewport + 0.5) {
        setState(() {
          _overflows = true;
          _scrollExtent = extent;
        });
        _animController.forward(from: 0);
      }
    });
  }

  void _tick() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    if (!_overflows) return;

    final elapsed = _animController.value * _cycleMs;
    final scroll = _scrollExtent + 20;

    double scrollProgress;
    if (elapsed < _scrollForwardMs) {
      // Scrolling forward
      scrollProgress = elapsed / _scrollForwardMs;
    } else if (elapsed < _scrollForwardMs + _pauseEndMs) {
      // Paused at end
      scrollProgress = 1.0;
    } else if (elapsed < _scrollForwardMs + _pauseEndMs + _scrollBackMs) {
      // Scrolling backward
      scrollProgress =
          1.0 - (elapsed - _scrollForwardMs - _pauseEndMs) / _scrollBackMs;
    } else {
      // Paused at start
      scrollProgress = 0.0;
    }

    final target = scrollProgress * scroll;
    if ((target - controller.position.pixels).abs() > 0.5) {
      controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _controller ??= ScrollController(),
          scrollDirection: Axis.horizontal,
          physics: _overflows
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
            ),
            child: Text(
              widget.text,
              maxLines: 1,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}

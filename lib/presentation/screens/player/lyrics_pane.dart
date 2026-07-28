import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/providers.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/database_service.dart';
import '../../../services/lingva_translate_service.dart';
import '../../components/app_feedback.dart';
import '../../dialogs/lyrics_search_sheet.dart';
import '../../dialogs/lyrics_translation_sheet.dart';
import '../../models/lyrics_gap_loader_state.dart';
import '../../tokens/player_tokens.dart';
import '../../widgets/lyrics_gap_loader.dart';
import '../../widgets/lyrics_line.dart';

/// Left pane. Content only — the shell owns the backdrop, header, pill and
/// transport dock. Do not add a Scaffold, AppBar or background here.
class LyricsPane extends ConsumerStatefulWidget {
  final Song song;
  final Color accent;

  const LyricsPane({
    super.key,
    required this.song,
    required this.accent,
  });

  @override
  ConsumerState<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends ConsumerState<LyricsPane>
    with AutomaticKeepAliveClientMixin {
  /// How far down the viewport the active line sits while auto-scrolling.
  static const double _activeLineAnchor = 0.38;

  /// Auto-scroll stays out of the way for this long after a manual scroll.
  static const Duration _manualScrollGrace = Duration(milliseconds: 2500);

  /// The gap loader only earns its place once the silence is long enough to
  /// read as a real instrumental break.
  static const Duration _gapLoaderDelay = Duration(seconds: 5);

  /// Below this the loader would barely finish appearing, so it stays away.
  static const Duration _minimumGapLoaderWindow = Duration(seconds: 3);

  /// Vertical space the find-lyrics button occupies at the top of the pane —
  /// its 48pt touch target plus the inset above it. The lyrics list pads by
  /// this much so a line never scrolls under the button.
  static const double _actionStripHeight = 48 + PlayerTokens.s1;

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  final LingvaTranslateService _translateService = LingvaTranslateService();

  List<LyricLine>? _lyrics;
  String? _rawLyricsContent;
  List<LyricLine>? _translatedLyrics;
  bool _translating = false;
  bool _hasCachedTranslation = false;
  bool _loading = true;
  bool _hasSynced = false;
  String? _loadedFilename;

  /// The playhead is followed off a subscription rather than a `StreamBuilder`
  /// around the list.
  ///
  /// `positionStream` emits about five times a second for as long as anything is
  /// playing, and wrapping the `ListView` in it rebuilt every lyric in the song —
  /// on every screen this pane is alive behind, whether or not anything visible
  /// had changed. What the list actually depends on is the *active line*, which
  /// changes every few seconds. Splitting the two means the ticks land on three
  /// small notifiers and the list rebuilds when the singing moves on.
  final ValueNotifier<int> _activeLine = ValueNotifier(-1);

  /// Index the gap loader is inserted before, or -1 when it is hidden. Changes
  /// once per instrumental break.
  final ValueNotifier<int> _gapSlot = ValueNotifier(-1);

  /// The loader's fill. This is the one thing here that genuinely wants every
  /// tick, so it is scoped to the loader widget alone.
  final ValueNotifier<double> _gapProgress = ValueNotifier(0);

  /// After the gap ends we keep the slot for one collapse animation so the
  /// reserved space can AnimatedSize shut instead of vanishing in a frame.
  Timer? _gapCollapseTimer;
  static const Duration _gapCollapseHold = PlayerTokens.dSlow;

  StreamSubscription<Duration>? _positionSub;
  DateTime? _lastManualScroll;

  /// Set while we drive the scroll ourselves, so our own motion is not
  /// mistaken for the user taking over.
  bool _autoScrolling = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onUserScroll);
    _positionSub = ref
        .read(audioPlayerManagerProvider)
        .player
        .positionStream
        .listen(_onPosition);
    _load();
  }

  @override
  void didUpdateWidget(LyricsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.filename != widget.song.filename) _load();
  }

  @override
  void dispose() {
    _gapCollapseTimer?.cancel();
    _positionSub?.cancel();
    _scrollController.removeListener(_onUserScroll);
    _scrollController.dispose();
    _activeLine.dispose();
    _gapSlot.dispose();
    _gapProgress.dispose();
    super.dispose();
  }

  /// Turns a playhead tick into the three things the pane actually renders from.
  /// Runs off the widget tree entirely: nothing here rebuilds unless one of the
  /// values changed.
  void _onPosition(Duration position) {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty || !_hasSynced) return;

    final active = _activeIndexFor(lyrics, position);
    if (active != _activeLine.value) {
      _activeLine.value = active;
      if (active >= 0) _maybeAutoScroll(active);
    }

    final gap = computeLyricsGapLoaderState(
      lyrics: lyrics,
      position: position,
      delay: _gapLoaderDelay,
      minimumWindow: _minimumGapLoaderWindow,
    );

    if (gap.shouldShow) {
      _gapCollapseTimer?.cancel();
      _gapCollapseTimer = null;
      _gapSlot.value = gap.insertBeforeLyricIndex;
      _gapProgress.value = gap.progress;
    } else if (_gapSlot.value >= 0 && _gapCollapseTimer == null) {
      // Drive the loader's own exit to completion, then clear the slot so
      // AnimatedSize can collapse the row height.
      _gapProgress.value = 1;
      _gapCollapseTimer = Timer(_gapCollapseHold, () {
        if (!mounted) return;
        _gapSlot.value = -1;
        _gapProgress.value = 0;
        _gapCollapseTimer = null;
      });
    }
  }

  void _onUserScroll() {
    // Only a user drag should suppress auto-scroll; our own motion must not.
    if (_autoScrolling || !_scrollController.hasClients) return;
    if (_scrollController.position.userScrollDirection !=
        ScrollDirection.idle) {
      _lastManualScroll = DateTime.now();
    }
  }

  Future<void> _load() async {
    final filename = widget.song.filename;
    _gapCollapseTimer?.cancel();
    _gapCollapseTimer = null;
    setState(() {
      _loading = true;
      _lyrics = null;
      _hasSynced = false;
      _loadedFilename = filename;
      _lineKeys.clear();
    });
    _activeLine.value = -1;
    _gapSlot.value = -1;
    _gapProgress.value = 0;

    // The repository caches to disk, so re-entering the pane is cheap.
    final content = await ref.read(songRepositoryProvider).getLyrics(
          widget.song,
        );

    if (!mounted || _loadedFilename != filename) return;

    final parsed = (content == null || content.trim().isEmpty)
        ? const <LyricLine>[]
        : LyricLine.parse(content);

    setState(() {
      _lyrics = parsed;
      _rawLyricsContent = content;
      _translatedLyrics = null;
      _hasCachedTranslation = false;
      _hasSynced = parsed.any((l) => l.isSynced);
      _loading = false;
    });

    if (parsed.isNotEmpty) {
      final settings = ref.read(settingsProvider);
      final cached = await DatabaseService.instance.getTranslatedLyrics(
        filename,
        settings.lyricsTargetLanguage,
      );

      if (!mounted || _loadedFilename != filename) return;

      if (cached == '[SAME_LANG]') {
        setState(() {
          _translatedLyrics = null;
          _hasCachedTranslation = false;
        });
      } else if (cached != null &&
          cached.trim().isNotEmpty &&
          cached.trim() != content?.trim()) {
        setState(() {
          _translatedLyrics = LyricLine.parse(cached);
          _hasCachedTranslation = true;
        });
      } else {
        if (cached != null && cached.trim() == content?.trim()) {
          await DatabaseService.instance
              .deleteTranslatedLyrics(filename, settings.lyricsTargetLanguage);
        }
        if (settings.lyricsAutoTranslate &&
            content != null &&
            content.trim().isNotEmpty) {
          _performTranslation(settings.lyricsTargetLanguage, silent: true);
        }
      }
    }

    // Land on the right line straight away rather than waiting for the next
    // playhead tick.
    _onPosition(ref.read(audioPlayerManagerProvider).player.position);
  }

  /// Looks lyrics up on LRCLIB and writes the chosen result into the file.
  ///
  /// The write bumps `lyricsRevisionProvider`, which is what reloads this pane —
  /// no explicit reload here, so applying from anywhere else refreshes it too.
  Future<void> _findLyricsOnline() async {
    final chosen = await showLyricsSearchSheet(context, song: widget.song);
    if (chosen == null || !mounted) return;

    try {
      await ref.read(songsProvider.notifier).updateLyrics(widget.song, chosen);
      if (mounted) appSnack(context, 'Lyrics saved', tone: AppTone.success);
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Could not save lyrics: $e', tone: AppTone.danger);
      }
    }
  }

  Future<void> _openTranslationSheet() async {
    final config = await showLyricsTranslationSheet(
      context,
      currentSongTitle: widget.song.title,
      hasCachedTranslation: _hasCachedTranslation,
    );

    if (config == null || !mounted) return;

    if (config.clearCache) {
      await DatabaseService.instance
          .deleteTranslatedLyrics(widget.song.filename);
      setState(() {
        _translatedLyrics = null;
        _hasCachedTranslation = false;
      });
      if (mounted) {
        appSnack(context, 'Cached translation cleared', tone: AppTone.info);
      }
      return;
    }

    if (config.translateNow) {
      await _performTranslation(config.targetLanguage);
    }
  }

  Future<void> _performTranslation(String targetLang, {bool silent = false}) async {
    final content = _rawLyricsContent;
    if (content == null || content.trim().isEmpty) return;

    final cached = await DatabaseService.instance.getTranslatedLyrics(
      widget.song.filename,
      targetLang,
    );

    if (cached == '[SAME_LANG]') {
      if (!mounted) return;
      setState(() {
        _translatedLyrics = null;
        _hasCachedTranslation = false;
      });
      return;
    }

    if (cached != null &&
        cached.trim().isNotEmpty &&
        cached.trim() != content.trim()) {
      if (!mounted) return;
      setState(() {
        _translatedLyrics = LyricLine.parse(cached);
        _hasCachedTranslation = true;
      });
      return;
    }

    if (_translateService.isAlreadyInTargetScript(content, targetLang)) {
      await DatabaseService.instance.saveTranslatedLyrics(
        widget.song.filename,
        targetLang,
        '[SAME_LANG]',
      );
      if (mounted) {
        setState(() {
          _translatedLyrics = null;
          _hasCachedTranslation = false;
        });
      }
      return;
    }

    setState(() {
      _translating = true;
    });

    try {
      final response = await _translateService.translateLyrics(
        lyrics: content,
        targetLang: targetLang,
      );

      final detected = response.detectedSourceLang?.toLowerCase();
      final target = targetLang.toLowerCase();

      final isSameLang = detected != null &&
          (detected == target || target.startsWith(detected));

      if (isSameLang) {
        await DatabaseService.instance.saveTranslatedLyrics(
          widget.song.filename,
          targetLang,
          '[SAME_LANG]',
        );

        if (!mounted) return;
        setState(() {
          _translatedLyrics = null;
          _hasCachedTranslation = false;
        });
        if (!silent) {
          appSnack(context, 'Lyrics are already in target language',
              tone: AppTone.info);
        }
      } else if (response.text.trim().isNotEmpty) {
        await DatabaseService.instance.saveTranslatedLyrics(
          widget.song.filename,
          targetLang,
          response.text,
        );

        if (!mounted) return;
        setState(() {
          _translatedLyrics = LyricLine.parse(response.text);
          _hasCachedTranslation = true;
        });
        appSnack(context, 'Lyrics translated', tone: AppTone.success);
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Translation failed: $e', tone: AppTone.danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _translating = false;
        });
      }
    }
  }

  int _activeIndexFor(List<LyricLine> lyrics, Duration position) {
    var active = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (!lyrics[i].isSynced) continue;
      if (lyrics[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  void _maybeAutoScroll(int index) {
    final since = _lastManualScroll;
    if (since != null &&
        DateTime.now().difference(since) < _manualScrollGrace) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;

      // Only lines currently built have a live context; ones far off-screen
      // will be scrolled to as they come into range.
      final ctx = _lineKeys[index]?.currentContext;
      if (ctx == null) {
        // Item not rendered yet (lazy builder). Jump to approximate offset
        // so the next frame's precise scroll can find it.
        const double estimatedHeight = 56;
        final pos = _scrollController.position;
        final roughTarget = (_actionStripHeight +
                index * estimatedHeight -
                pos.viewportDimension * _activeLineAnchor)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        pos.jumpTo(roughTarget);
        _maybeAutoScroll(index);
        return;
      }

      // Deliberately not Scrollable.ensureVisible: it walks *every* enclosing
      // scrollable, so from inside the shell's PageView it would drag the user
      // back to this pane whenever a line changed while they were on another.
      // RenderAbstractViewport.maybeOf stops at our own ListView.
      final box = ctx.findRenderObject() as RenderBox?;
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      if (box == null || viewport == null) return;

      final position = _scrollController.position;
      final target = viewport
          .getOffsetToReveal(box, _activeLineAnchor)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);

      if ((target - position.pixels).abs() < 1) return;

      _autoScrolling = true;
      try {
        await _scrollController.animateTo(
          target,
          duration: PlayerTokens.dSlow,
          curve: PlayerTokens.cStandard,
        );
      } finally {
        _autoScrolling = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Lyrics live in the audio file, not in provider state, so a write
    // elsewhere is invisible from here. The revision counter is the signal.
    ref.listen(lyricsRevisionProvider, (_, __) => _load());

    return Stack(
      children: [
        Positioned.fill(child: _buildContent(context)),
        // Kept inside the pane rather than in the shell header: the shell owns
        // the chrome, and this action belongs to the lyrics view alone. The
        // list reserves [_actionStripHeight] at the top so no lyric ever passes
        // underneath it.
        Positioned(
          top: PlayerTokens.s1,
          right: PlayerTokens.s3,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: _translating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _hasCachedTranslation
                            ? Icons.g_translate_rounded
                            : Icons.translate_rounded,
                      ),
                color: _hasCachedTranslation
                    ? widget.accent
                    : Colors.white.withValues(alpha: PlayerTokens.aSecondary),
                tooltip: 'Translate lyrics',
                onPressed: _translating ? null : _openTranslationSheet,
              ),
              IconButton(
                icon: const Icon(Icons.travel_explore_rounded),
                color: Colors.white.withValues(alpha: PlayerTokens.aSecondary),
                tooltip: 'Find lyrics online',
                onPressed: _findLyricsOnline,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final lyrics = _lyrics ?? const <LyricLine>[];
    if (lyrics.isEmpty) return _buildEmptyState(context);

    final player = ref.watch(audioPlayerManagerProvider).player;
    final settings = ref.watch(settingsProvider);
    final blurEnabled = settings.lyricsBlurOverlayEnabled;
    final hasSynced = _hasSynced;

    // Rebuilds when the singing moves on or a gap opens — not on every tick of
    // the playhead.
    return ListenableBuilder(
      listenable: Listenable.merge([_activeLine, _gapSlot]),
      builder: (context, _) {
        final active = _activeLine.value;
        final gapSlot = _gapSlot.value;

        return ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          // Top padding is deliberately small: the first lines belong near the
          // top of the pane, not floating mid-screen. It only clears the
          // find-lyrics button. The tall bottom padding is what lets the last
          // lines still scroll up to the anchor.
          padding: EdgeInsets.only(
            top: _actionStripHeight,
            bottom: MediaQuery.of(context).size.height * 0.22,
          ),
          itemCount: lyrics.length,
          itemBuilder: (context, index) {
            final line = lyrics[index];
            final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

            String? lineTranslation;
            if (_translatedLyrics != null &&
                index < _translatedLyrics!.length) {
              lineTranslation = _translatedLyrics![index].text;
            }

            final lyricWidget = KeyedSubtree(
              key: key,
              child: LyricsLine(
                text: line.text,
                translatedText: lineTranslation,
                translationMode: settings.lyricsTranslationMode,
                isActive: index == active,
                isPlayed: active >= 0 && index <= active,
                hasTime: line.isSynced,
                blurSigma: _blurFor(
                  index: index,
                  active: active,
                  enabled: blurEnabled && hasSynced,
                ),
                activeFontSize: 24,
                inactiveFontSize: 22,
                activeColor: widget.accent,
                glowIntensity: index == active ? 1.0 : 0.0,
                onTap: () => player.seek(line.time),
              ),
            );

            // AnimatedSize on every row so opening/closing a gap grows and
            // shrinks the reserved space instead of popping the list.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: PlayerTokens.dSlow,
                  curve: PlayerTokens.cStandard,
                  alignment: Alignment.topCenter,
                  child: gapSlot == index
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PlayerTokens.s5,
                            vertical: PlayerTokens.s3,
                          ),
                          // The only thing in the pane that follows the
                          // playhead continuously, and it rebuilds nothing
                          // but itself.
                          child: ValueListenableBuilder<double>(
                            valueListenable: _gapProgress,
                            builder: (context, progress, _) => LyricsGapLoader(
                              progress: progress,
                              accent: widget.accent,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                lyricWidget,
              ],
            );
          },
        );
      },
    );
  }

  /// Unfocused lines blur out with distance from the active line, so the eye
  /// lands on the line being sung.
  double _blurFor({
    required int index,
    required int active,
    required bool enabled,
  }) {
    if (!enabled || active < 0 || index == active) return 0;
    final distance = (index - active).abs();
    return (distance * 0.9).clamp(0.0, 3.2);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PlayerTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 44,
              color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
            ),
            const SizedBox(height: PlayerTokens.s3),
            Text('No lyrics', style: PlayerTokens.paneTitle(context)),
            const SizedBox(height: PlayerTokens.s1),
            Text(
              'This track has no embedded lyrics.',
              textAlign: TextAlign.center,
              style: PlayerTokens.trackSubtitle(context),
            ),
            const SizedBox(height: PlayerTokens.s5),
            FilledButton.icon(
              onPressed: _findLyricsOnline,
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('Find lyrics online'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: PlayerTokens.onAccent(widget.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

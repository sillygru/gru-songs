import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/providers.dart';
import '../../../providers/settings_provider.dart';
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

  static const Duration _minimumRemainingGap = Duration(seconds: 3);

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};

  List<LyricLine>? _lyrics;
  bool _loading = true;
  String? _loadedFilename;

  int _activeIndex = -1;
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
    _load();
  }

  @override
  void didUpdateWidget(LyricsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.filename != widget.song.filename) _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onUserScroll);
    _scrollController.dispose();
    super.dispose();
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
    setState(() {
      _loading = true;
      _lyrics = null;
      _activeIndex = -1;
      _loadedFilename = filename;
      _lineKeys.clear();
    });

    // The repository caches to disk, so re-entering the pane is cheap.
    final content = await ref.read(songRepositoryProvider).getLyrics(
          widget.song,
        );

    if (!mounted || _loadedFilename != filename) return;

    setState(() {
      _lyrics = (content == null || content.trim().isEmpty)
          ? const []
          : LyricLine.parse(content);
      _loading = false;
    });
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
      if (ctx == null) return;

      _autoScrolling = true;
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: _activeLineAnchor,
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
    final hasSynced = lyrics.any((l) => l.isSynced);

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final active = hasSynced ? _activeIndexFor(lyrics, position) : -1;

        if (active != _activeIndex) {
          _activeIndex = active;
          if (active >= 0) _maybeAutoScroll(active);
        }

        final gap = hasSynced
            ? computeLyricsGapLoaderState(
                lyrics: lyrics,
                position: position,
                delay: const Duration(seconds: 2),
                minimumRemainingGap: _minimumRemainingGap,
              )
            : LyricsGapLoaderState.hidden;

        return ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.22,
          ),
          itemCount: lyrics.length,
          itemBuilder: (context, index) {
            final line = lyrics[index];
            final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

            final lyricWidget = KeyedSubtree(
              key: key,
              child: LyricsLine(
                text: line.text,
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

            if (gap.shouldShow && gap.insertBeforeLyricIndex == index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PlayerTokens.s5,
                      vertical: PlayerTokens.s3,
                    ),
                    child: LyricsGapLoader(animationDuration: gap.remainingGap),
                  ),
                  lyricWidget,
                ],
              );
            }

            return lyricWidget;
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
          ],
        ),
      ),
    );
  }
}

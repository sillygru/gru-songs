import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../tokens/player_tokens.dart';

/// The current synced-lyric line, shown under the title on the now-playing
/// pane — the Spotify-style peek. It only appears when the track actually has
/// time-synced lyrics; unsynced or missing lyrics render nothing at all, so the
/// pane keeps its shape.
///
/// This reuses the same lyrics source and active-line logic as [LyricsPane]
/// (the repository's disk-cached `getLyrics` and the "last synced line whose
/// timestamp has passed" rule), so the peek and the full lyrics pane can never
/// disagree about which line is current.
class NowPlayingLyricPeek extends ConsumerStatefulWidget {
  final Song song;
  final Color accent;

  const NowPlayingLyricPeek({
    super.key,
    required this.song,
    required this.accent,
  });

  @override
  ConsumerState<NowPlayingLyricPeek> createState() =>
      _NowPlayingLyricPeekState();
}

class _NowPlayingLyricPeekState extends ConsumerState<NowPlayingLyricPeek> {
  List<LyricLine> _lines = const [];
  bool _hasSynced = false;
  String? _loadedFilename;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NowPlayingLyricPeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.filename != widget.song.filename) _load();
  }

  Future<void> _load() async {
    final filename = widget.song.filename;
    _loadedFilename = filename;
    _hasSynced = false;
    _lines = const [];

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
    if (!_hasSynced) return const SizedBox.shrink();

    final player = ref.watch(audioPlayerManagerProvider).player;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PlayerTokens.s5),
      child: SizedBox(
        height: 24,
        child: StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final active = _activeIndexFor(position);
            final text = active >= 0 ? _lines[active].text.trim() : '';

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
              child: text.isEmpty
                  ? const SizedBox.shrink(key: ValueKey('lyric-peek-empty'))
                  : Text(
                      text,
                      key: ValueKey(text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

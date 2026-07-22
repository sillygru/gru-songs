import '../../models/song.dart';

class LyricsGapLoaderState {
  final bool shouldShow;
  final int insertBeforeLyricIndex;

  /// How far through the visible window we are, 0 at the moment the loader
  /// appears and 1 when the next lyric lands. Drives the dot fill, so the
  /// animation is a function of playback position rather than wall clock.
  final double progress;

  const LyricsGapLoaderState({
    required this.shouldShow,
    required this.insertBeforeLyricIndex,
    required this.progress,
  });

  static const hidden = LyricsGapLoaderState(
    shouldShow: false,
    insertBeforeLyricIndex: -1,
    progress: 0,
  );
}

/// Resolves the window `[windowStart, windowEnd]` into visibility and progress.
///
/// Visibility is decided by the window's *length*, not by how much of it is
/// left: once the loader is on screen it stays until the lyric arrives, so its
/// exit animation has room to play instead of popping out early.
LyricsGapLoaderState _stateForWindow({
  required Duration position,
  required Duration windowStart,
  required Duration windowEnd,
  required Duration minimumWindow,
  required int insertBeforeLyricIndex,
}) {
  final span = windowEnd.inMicroseconds - windowStart.inMicroseconds;
  if (span < minimumWindow.inMicroseconds ||
      position < windowStart ||
      position >= windowEnd) {
    return LyricsGapLoaderState.hidden;
  }

  final elapsed = position.inMicroseconds - windowStart.inMicroseconds;
  return LyricsGapLoaderState(
    shouldShow: true,
    insertBeforeLyricIndex: insertBeforeLyricIndex,
    progress: (elapsed / span).clamp(0.0, 1.0),
  );
}

LyricsGapLoaderState computeLyricsGapLoaderState({
  required List<LyricLine> lyrics,
  required Duration position,
  required Duration delay,
  required Duration minimumWindow,
}) {
  final syncedEntries = <(int, LyricLine)>[];
  for (var i = 0; i < lyrics.length; i++) {
    final line = lyrics[i];
    if (line.isSynced) {
      syncedEntries.add((i, line));
    }
  }

  if (syncedEntries.isEmpty) {
    return LyricsGapLoaderState.hidden;
  }

  int activeSyncedEntry = -1;
  for (var i = 0; i < syncedEntries.length; i++) {
    if (syncedEntries[i].$2.time <= position) {
      activeSyncedEntry = i;
    } else {
      break;
    }
  }

  // Intro gap: the silence starts at zero, so the window opens at [delay].
  if (activeSyncedEntry < 0) {
    return _stateForWindow(
      position: position,
      windowStart: delay,
      windowEnd: syncedEntries.first.$2.time,
      minimumWindow: minimumWindow,
      insertBeforeLyricIndex: syncedEntries.first.$1,
    );
  }

  final nextEntryIndex = activeSyncedEntry + 1;
  if (nextEntryIndex >= syncedEntries.length) {
    return LyricsGapLoaderState.hidden;
  }

  return _stateForWindow(
    position: position,
    windowStart: syncedEntries[activeSyncedEntry].$2.time + delay,
    windowEnd: syncedEntries[nextEntryIndex].$2.time,
    minimumWindow: minimumWindow,
    insertBeforeLyricIndex: syncedEntries[nextEntryIndex].$1,
  );
}

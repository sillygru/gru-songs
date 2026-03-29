import '../../models/song.dart';

class LyricsGapLoaderState {
  final bool shouldShow;
  final int insertBeforeLyricIndex;
  final Duration remainingGap;

  const LyricsGapLoaderState({
    required this.shouldShow,
    required this.insertBeforeLyricIndex,
    required this.remainingGap,
  });

  static const hidden = LyricsGapLoaderState(
    shouldShow: false,
    insertBeforeLyricIndex: -1,
    remainingGap: Duration.zero,
  );
}

LyricsGapLoaderState computeLyricsGapLoaderState({
  required List<LyricLine> lyrics,
  required Duration position,
  required Duration delay,
  required Duration minimumRemainingGap,
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

  if (activeSyncedEntry < 0) {
    final firstLine = syncedEntries.first.$2;
    final remainingGap = firstLine.time - position;
    if (firstLine.time <= delay ||
        position < delay ||
        position >= firstLine.time ||
        remainingGap < minimumRemainingGap) {
      return LyricsGapLoaderState.hidden;
    }
    return LyricsGapLoaderState(
      shouldShow: true,
      insertBeforeLyricIndex: syncedEntries.first.$1,
      remainingGap: remainingGap,
    );
  }

  final nextEntryIndex = activeSyncedEntry + 1;
  if (nextEntryIndex >= syncedEntries.length) {
    return LyricsGapLoaderState.hidden;
  }

  final currentLine = syncedEntries[activeSyncedEntry].$2;
  final nextLine = syncedEntries[nextEntryIndex].$2;
  final gapElapsed = position - currentLine.time;
  final remainingGap = nextLine.time - position;

  if (gapElapsed < delay ||
      position >= nextLine.time ||
      remainingGap < minimumRemainingGap) {
    return LyricsGapLoaderState.hidden;
  }

  return LyricsGapLoaderState(
    shouldShow: true,
    insertBeforeLyricIndex: syncedEntries[nextEntryIndex].$1,
    remainingGap: remainingGap,
  );
}

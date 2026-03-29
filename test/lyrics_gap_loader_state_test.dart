import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/presentation/models/lyrics_gap_loader_state.dart';

void main() {
  const delay = Duration(seconds: 4);
  const minimumRemainingGap = Duration(milliseconds: 1200);

  List<LyricLine> buildLyrics() {
    return const [
      LyricLine(
        time: Duration(seconds: 5),
        text: 'First',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 12),
        text: 'Second',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 20),
        text: 'Third',
        isSynced: true,
      ),
    ];
  }

  test('stays hidden before delay during intro gap', () {
    final state = computeLyricsGapLoaderState(
      lyrics: buildLyrics(),
      position: const Duration(seconds: 3),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isFalse);
  });

  test('appears after delay before first lyric', () {
    const lyrics = [
      LyricLine(
        time: Duration(seconds: 7),
        text: 'First',
        isSynced: true,
      ),
    ];

    final state = computeLyricsGapLoaderState(
      lyrics: lyrics,
      position: const Duration(seconds: 4, milliseconds: 100),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isTrue);
    expect(state.insertBeforeLyricIndex, 0);
  });

  test('appears after delay in mid-song gap and points at next lyric', () {
    final state = computeLyricsGapLoaderState(
      lyrics: buildLyrics(),
      position: const Duration(seconds: 9, milliseconds: 200),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isTrue);
    expect(state.insertBeforeLyricIndex, 1);
  });

  test('stays hidden for short gaps', () {
    final lyrics = const [
      LyricLine(
        time: Duration(seconds: 1),
        text: 'One',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 4),
        text: 'Two',
        isSynced: true,
      ),
    ];

    final state = computeLyricsGapLoaderState(
      lyrics: lyrics,
      position: const Duration(seconds: 3),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isFalse);
  });

  test('does not appear after final synced lyric', () {
    final state = computeLyricsGapLoaderState(
      lyrics: buildLyrics(),
      position: const Duration(seconds: 26),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isFalse);
  });

  test('does not appear for unsynced lyrics', () {
    final lyrics = const [
      LyricLine(time: Duration.zero, text: 'Plain line'),
      LyricLine(time: Duration.zero, text: 'Another line'),
    ];

    final state = computeLyricsGapLoaderState(
      lyrics: lyrics,
      position: const Duration(seconds: 6),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isFalse);
  });

  test('stays hidden when remaining gap is too short after crossing delay', () {
    final state = computeLyricsGapLoaderState(
      lyrics: buildLyrics(),
      position: const Duration(seconds: 11, milliseconds: 200),
      delay: delay,
      minimumRemainingGap: minimumRemainingGap,
    );

    expect(state.shouldShow, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/presentation/models/lyrics_gap_loader_state.dart';

void main() {
  const delay = Duration(seconds: 5);
  const minimumWindow = Duration(seconds: 3);

  List<LyricLine> buildLyrics() {
    return const [
      LyricLine(
        time: Duration(seconds: 10),
        text: 'First',
        isSynced: true,
      ),
      // 20s gap — window runs 15s..30s once the 5s delay elapses.
      LyricLine(
        time: Duration(seconds: 30),
        text: 'Second',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 34),
        text: 'Third',
        isSynced: true,
      ),
    ];
  }

  LyricsGapLoaderState stateAt(Duration position, {List<LyricLine>? lyrics}) {
    return computeLyricsGapLoaderState(
      lyrics: lyrics ?? buildLyrics(),
      position: position,
      delay: delay,
      minimumWindow: minimumWindow,
    );
  }

  group('visibility', () {
    test('stays hidden before the delay during the intro gap', () {
      expect(stateAt(const Duration(seconds: 4)).shouldShow, isFalse);
    });

    test('appears after the delay before the first lyric', () {
      final state = stateAt(const Duration(seconds: 6));

      expect(state.shouldShow, isTrue);
      expect(state.insertBeforeLyricIndex, 0);
    });

    test('stays hidden before the delay in a mid-song gap', () {
      expect(stateAt(const Duration(seconds: 14)).shouldShow, isFalse);
    });

    test('appears after the delay and points at the next lyric', () {
      final state = stateAt(const Duration(seconds: 16));

      expect(state.shouldShow, isTrue);
      expect(state.insertBeforeLyricIndex, 1);
    });

    test('stays hidden for gaps too short to fit the window', () {
      // 4s gap: the window is only 30s..34s minus the 5s delay, i.e. negative.
      expect(stateAt(const Duration(seconds: 32)).shouldShow, isFalse);
    });

    test('stays hidden after the final synced lyric', () {
      expect(stateAt(const Duration(seconds: 40)).shouldShow, isFalse);
    });

    test('stays hidden for unsynced lyrics', () {
      const lyrics = [
        LyricLine(time: Duration.zero, text: 'Plain line'),
        LyricLine(time: Duration.zero, text: 'Another line'),
      ];

      expect(stateAt(const Duration(seconds: 6), lyrics: lyrics).shouldShow,
          isFalse);
    });

    test('remains visible right up to the next lyric', () {
      // The exit animation needs the tail of the window, so the loader must not
      // wink out early the way the old remaining-gap gate made it.
      final state = stateAt(const Duration(seconds: 29, milliseconds: 900));

      expect(state.shouldShow, isTrue);
      expect(state.progress, greaterThan(0.98));
    });

    test('is gone once the next lyric lands', () {
      expect(stateAt(const Duration(seconds: 30)).shouldShow, isFalse);
    });
  });

  group('progress', () {
    test('starts at zero when the mid-song loader appears', () {
      expect(stateAt(const Duration(seconds: 15)).progress, 0);
    });

    test('is half way through the middle of the mid-song window', () {
      // Window 15s..30s, so the midpoint is 22.5s.
      expect(
        stateAt(const Duration(seconds: 22, milliseconds: 500)).progress,
        closeTo(0.5, 0.001),
      );
    });

    test('tracks the intro window from the delay to the first lyric', () {
      // Window 5s..10s, so 7.5s is the midpoint.
      expect(
        stateAt(const Duration(seconds: 7, milliseconds: 500)).progress,
        closeTo(0.5, 0.001),
      );
    });

    test('advances monotonically across the window', () {
      var previous = -1.0;
      for (var ms = 15000; ms < 30000; ms += 250) {
        final state = stateAt(Duration(milliseconds: ms));
        expect(state.shouldShow, isTrue, reason: 'hidden at ${ms}ms');
        expect(state.progress, greaterThanOrEqualTo(previous));
        previous = state.progress;
      }
    });

    test('is zero when hidden', () {
      expect(stateAt(const Duration(seconds: 4)).progress, 0);
    });
  });
}

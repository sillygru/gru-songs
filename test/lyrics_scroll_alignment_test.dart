import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/screens/player/lyrics_pane.dart';

void main() {
  const actionStripHeight = 52.0;
  const estimatedLineHeight = 56.0;
  const activeLineAnchor = 0.38;
  const retryViewportStep = 0.5;
  const viewport = 700.0;

  double attemptOffset({
    required int index,
    required int attempt,
    double minExtent = 0,
    double maxExtent = 20000,
  }) {
    return LyricsPane.scrollAttemptOffset(
      index: index,
      attempt: attempt,
      actionStripHeight: actionStripHeight,
      estimatedLineHeight: estimatedLineHeight,
      activeLineAnchor: activeLineAnchor,
      retryViewportStep: retryViewportStep,
      viewport: viewport,
      minExtent: minExtent,
      maxExtent: maxExtent,
    );
  }

  group('attempt 0', () {
    test('parks the line at the anchor on the estimated height', () {
      // 52 + 100*56 - 700*0.38 puts line 100 at 38% of a 700px viewport.
      expect(attemptOffset(index: 100, attempt: 0), 5386);
    });
  });

  group('retries', () {
    test('walk the viewport down past a fallen-short estimate', () {
      final attempts = [
        for (var i = 0; i < 5; i++) attemptOffset(index: 100, attempt: i)
      ];
      expect(attempts, [5386, 5736, 6086, 6436, 6786]);
    });

    test('make monotonic forward progress so they never stall on one spot', () {
      var previous = -1.0;
      for (var i = 0; i < 20; i++) {
        final offset = attemptOffset(index: 120, attempt: i);
        expect(offset, greaterThan(previous));
        previous = offset;
      }
    });

    test('reach a line that is taller than the estimate', () {
      // All lines 77px (subtext translation): line 90's real top is at 6982,
      // below the attempt-0 estimate of 4826. The retries must pass over it so
      // the lazy list actually builds the line.
      const trueLineTop = actionStripHeight + 90 * 77;
      var reached = false;
      for (var i = 0; i < 10; i++) {
        final offset = attemptOffset(index: 90, attempt: i);
        if (offset >= trueLineTop - viewport + 1) {
          reached = true;
          break;
        }
      }
      expect(reached, isTrue);
    });

    test('stay within the scroll range', () {
      expect(attemptOffset(index: 300, attempt: 5, maxExtent: 8000), 8000);
      expect(attemptOffset(index: 0, attempt: 0, minExtent: 500), 500);
    });
  });
}

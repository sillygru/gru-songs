import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/beat_map.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/presentation/widgets/player_motion.dart';

/// A 120 BPM grid: a beat every 500ms, downbeats every fourth.
BeatMap gridMap({
  int beats = 16,
  int periodMs = 500,
  double strength = 1.0,
}) {
  final beatsMs = Int32List(beats);
  final strengths = Float32List(beats);
  final downbeats = Uint8List(beats);
  for (var i = 0; i < beats; i++) {
    beatsMs[i] = i * periodMs;
    strengths[i] = strength;
    downbeats[i] = i % 4 == 0 ? 1 : 0;
  }

  // Flat mid-level bands, so band-driven terms stay constant and the beat
  // envelope is what the assertions actually measure.
  final frames = (beats * periodMs / 1000 * BeatMap.bandFps).ceil();
  final bands = Uint8List(frames * BeatBand.values.length)
    ..fillRange(0, frames * BeatBand.values.length, 128);

  return BeatMap(
    version: BeatMap.currentVersion,
    durationMs: beats * periodMs,
    bpm: 60000 / periodMs,
    beatsMs: beatsMs,
    beatStrength: strengths,
    downbeats: downbeats,
    bands: bands,
  );
}

void main() {
  group('beat envelope', () {
    late PlayerMotionController controller;

    setUp(() {
      // No AudioPlayer is constructed: computeFrame is pure, which is the point
      // of keeping the frame math separable from the ticker.
      controller = PlayerMotionController.forTesting();
      controller.beatMap = gridMap();
    });

    tearDown(() => controller.dispose());

    test('peaks shortly after the beat, not on it', () {
      // A struck object reaches full displacement a beat late, not instantly.
      final onBeat = controller.computeFrame(2000).pulse;
      final justAfter = controller.computeFrame(2044).pulse;

      expect(onBeat, lessThan(justAfter));
      expect(justAfter, closeTo(1.0, 0.02));
    });

    test('decays away well before the next beat', () {
      // Both samples sit inside the same beat, so this measures decay alone.
      final atPeak = controller.computeFrame(2044).pulse;
      final late = controller.computeFrame(2440).pulse;

      expect(late, lessThan(atPeak * 0.25));
    });

    test('anticipation dips negative just before a beat', () {
      // 40ms out from the beat at 2500ms: inside the 60ms anticipation window.
      final frame = controller.computeFrame(2460);

      expect(frame.anticipation, lessThan(0));
      expect(frame.displacement, lessThan(frame.pulse));
    });

    test('anticipation deepens as the beat approaches', () {
      final early = controller.computeFrame(2450).anticipation;
      final later = controller.computeFrame(2490).anticipation;

      expect(later, lessThan(early));
    });

    test('no anticipation outside the window', () {
      expect(controller.computeFrame(2300).anticipation, 0);
    });

    test('downbeats punch harder than offbeats', () {
      // Beat 4 (2000ms) is a downbeat; beat 5 (2500ms) is not. Both carry the
      // same raw strength, so any difference is the bar accent alone.
      final downbeat = controller.computeFrame(2044);
      final offbeat = controller.computeFrame(2544);

      expect(downbeat.isDownbeat, isTrue);
      expect(offbeat.isDownbeat, isFalse);
      expect(downbeat.pulse, greaterThan(offbeat.pulse));
    });

    test('full-strength downbeats stay distinguishable instead of clamping',
        () {
      // Normalisation puts most beats near 1.0. If the accent were applied as a
      // multiplier upward, every beat would saturate and the bar would flatten.
      controller.beatMap = gridMap(strength: 1.0);

      final downbeat = controller.computeFrame(2044).pulse;
      final offbeat = controller.computeFrame(2544).pulse;

      expect(downbeat, closeTo(1.0, 0.02));
      expect(offbeat, lessThan(0.8));
    });

    test('before the first beat there is no pulse', () {
      controller.beatMap = gridMap(beats: 4, periodMs: 500);
      // Shift the grid forward so there is dead air at the start.
      expect(controller.computeFrame(-100).pulse, 0);
    });

    test('pulse never exceeds 1', () {
      controller.beatMap = gridMap(strength: 1.0);
      for (var ms = 0; ms < 8000; ms += 7) {
        expect(controller.computeFrame(ms.toDouble()).pulse,
            inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('without a beat grid', () {
    late PlayerMotionController controller;

    setUp(() => controller = PlayerMotionController.forTesting());
    tearDown(() => controller.dispose());

    test('an absent map still breathes rather than sitting dead', () {
      // Ambient tracks and not-yet-analysed tracks live here. A frozen cover
      // would read as a bug, so there must always be motion.
      var minimum = double.infinity;
      var maximum = double.negativeInfinity;
      for (var ms = 0; ms < 12000; ms += 50) {
        final breath = controller.computeFrame(ms.toDouble()).breath;
        minimum = breath < minimum ? breath : minimum;
        maximum = breath > maximum ? breath : maximum;
      }

      expect(maximum - minimum, greaterThan(0.2));
      expect(controller.computeFrame(0).hasBeat, isFalse);
    });

    test('a beatless map keeps its band energy', () {
      final frames = 300 * BeatBand.values.length;
      controller.beatMap = BeatMap(
        version: BeatMap.currentVersion,
        durationMs: 10000,
        bpm: 0,
        beatsMs: Int32List(0),
        beatStrength: Float32List(0),
        downbeats: Uint8List(0),
        bands: Uint8List(frames)..fillRange(0, frames, 200),
      );

      final frame = controller.computeFrame(1000);
      expect(frame.hasBeat, isFalse);
      expect(frame.bass, closeTo(200 / 255, 0.01));
      expect(frame.pulse, 0);
    });
  });

  group('intensity', () {
    test('scales monotonically across the three settings', () {
      final subtle = MotionIntensitySpec.of(PlayerMotionIntensity.subtle);
      final balanced = MotionIntensitySpec.of(PlayerMotionIntensity.balanced);
      final bold = MotionIntensitySpec.of(PlayerMotionIntensity.bold);

      expect(subtle.coverPunch, lessThan(balanced.coverPunch));
      expect(balanced.coverPunch, lessThan(bold.coverPunch));
      expect(subtle.particleCount, lessThan(balanced.particleCount));
      expect(balanced.particleCount, lessThan(bold.particleCount));
    });

    test('subtle stays visually restrained', () {
      // The default must read as "alive", not "bouncing". Cover scale tops out
      // just under 5% at a full-strength downbeat.
      final subtle = MotionIntensitySpec.of(PlayerMotionIntensity.subtle);
      final peakScale = 1 + subtle.coverPunch + subtle.coverBreath;

      expect(peakScale, lessThan(1.05));
    });
  });

  group('playhead clock', () {
    late PlayerMotionController controller;

    setUp(() => controller = PlayerMotionController.forTesting());
    tearDown(() => controller.dispose());

    test('small drift is eased, not snapped', () {
      controller.debugSetAnchor(const Duration(milliseconds: 1000));

      // 100ms of jitter: correct a fraction of it, so the pulse does not hitch.
      controller.debugOnPosition(const Duration(milliseconds: 1100));

      final position = controller.debugPredictedMs();
      expect(position, greaterThan(1000));
      expect(position, lessThan(1100));
    });

    test('a seek past the threshold snaps', () {
      controller.debugSetAnchor(const Duration(milliseconds: 1000));

      controller.debugOnPosition(const Duration(milliseconds: 60000));

      expect(controller.debugPredictedMs(), closeTo(60000, 5));
    });

    test('repeated easing converges on the true position', () {
      controller.debugSetAnchor(const Duration(milliseconds: 1000));

      for (var i = 0; i < 40; i++) {
        controller.debugOnPosition(const Duration(milliseconds: 1100));
      }

      expect(controller.debugPredictedMs(), closeTo(1100, 5));
    });

    test('latency offset shifts the visual position backwards', () {
      controller.debugSetAnchor(const Duration(milliseconds: 5000));

      controller.latencyMs = 0;
      final without = controller.debugVisualPositionMs();
      controller.latencyMs = 200;
      final with200 = controller.debugVisualPositionMs();

      // The listener hears position P-200ms at the instant the decoder is at P.
      expect(without - with200, closeTo(200, 1));
    });

    test('a paused clock does not advance', () {
      controller.debugSetAnchor(const Duration(milliseconds: 3000));

      final first = controller.debugPredictedMs();
      final second = controller.debugPredictedMs();

      expect(first, 3000);
      expect(second, 3000);
    });
  });
}

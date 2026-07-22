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

    test('settles past rest after the punch instead of easing straight back',
        () {
      // Nothing physical returns to where it started in a straight line. The
      // overshoot is what sells the cover as struck rather than faded.
      final atPeak = controller.computeFrame(2044);
      final settling = controller.computeFrame(2210);

      expect(atPeak.rebound, lessThan(0));
      expect(settling.rebound, lessThan(atPeak.rebound));
      // ...and it is back near rest before the next beat arrives.
      expect(controller.computeFrame(2480).rebound, greaterThan(-0.05));
    });

    test('the rebound is a settle, not a second punch', () {
      for (var ms = 0; ms < 8000; ms += 7) {
        final frame = controller.computeFrame(ms.toDouble());
        expect(frame.rebound, inInclusiveRange(-0.2, 0.0));
      }
    });

    test('the lean alternates side to side between beats', () {
      // A gesture that repeats identically is a metronome. Consecutive beats
      // have to fall the other way.
      final first = controller.computeFrame(2044).sway;
      final second = controller.computeFrame(2544).sway;
      final third = controller.computeFrame(3044).sway;

      expect(first * second, lessThan(0));
      expect(second * third, lessThan(0));
    });

    test('the lean varies in depth rather than repeating exactly', () {
      // Same beat position in three different bars: same direction, different
      // amounts.
      final depths = [2044, 4044, 6044]
          .map((ms) => controller.computeFrame(ms.toDouble()).sway.abs())
          .toList();

      expect(depths.toSet().length, 3);
    });

    test('the same beat always leans the same way', () {
      // Deterministic, so a track does not shuffle its gestures between plays.
      expect(controller.computeFrame(2044).sway,
          controller.computeFrame(2044).sway);
    });

    test('pulse never exceeds 1', () {
      controller.beatMap = gridMap(strength: 1.0);
      for (var ms = 0; ms < 8000; ms += 7) {
        expect(controller.computeFrame(ms.toDouble()).pulse,
            inInclusiveRange(0.0, 1.0));
      }
    });
  });

  // 340ms per beat is ~176 BPM: hardstyle and drum & bass territory. The
  // envelope used to be fixed in milliseconds, so at this tempo the punch was
  // still at ~23% of peak when the next beat landed and successive hits piled
  // onto a raised plateau instead of resolving — the cover read as one slow
  // swell rather than the fast train of pulses the music actually has.
  group('fast tempo', () {
    late PlayerMotionController controller;
    const periodMs = 340;

    setUp(() {
      controller = PlayerMotionController.forTesting();
      controller.beatMap = gridMap(beats: 32, periodMs: periodMs);
    });

    tearDown(() => controller.dispose());

    test('the punch resolves before the next beat instead of smearing', () {
      // Beat 8 is a downbeat at 2720ms; the next lands at 3060ms.
      final peak = controller.computeFrame(2720 + 44).pulse;
      final justBeforeNext = controller.computeFrame(3060 - 10).pulse;

      expect(peak, closeTo(1.0, 0.03));
      expect(
        justBeforeNext,
        lessThan(peak * 0.12),
        reason: 'the pulse was still at '
            '${(justBeforeNext / peak * 100).toStringAsFixed(0)}% of peak when '
            'the next beat arrived, so hits stack instead of separating',
      );
    });

    test('the settle finishes before the next anticipation opens', () {
      // The dip belongs to the beat at 3060ms and opens 54ms out.
      final rebound = controller.computeFrame(3060 - 60).rebound;

      expect(rebound, 0);
    });

    test('offbeats keep up with downbeats at speed', () {
      // Every beat is a full kick at this tempo; holding three in four down to
      // 62% is what made fast tracks read as one pulse per bar.
      final downbeat = controller.computeFrame(2720 + 44).pulse;
      final offbeat = controller.computeFrame(3060 + 44).pulse;

      expect(offbeat, greaterThan(downbeat * 0.8));
      // ...but the bar still has some shape.
      expect(offbeat, lessThan(downbeat));
    });

    test('a slow grid keeps its full bar accent', () {
      // The flattening is tempo-driven, not a blanket loosening: at 120 BPM the
      // accent is exactly what it was.
      controller.beatMap = gridMap(periodMs: 500);

      final downbeat = controller.computeFrame(2044).pulse;
      final offbeat = controller.computeFrame(2544).pulse;

      expect(offbeat / downbeat, closeTo(0.62, 0.01));
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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/beat_map.dart';
import 'package:wispie/domain/services/spectrum_bars.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/presentation/widgets/spectrum_controller.dart';

/// A map whose four bands hold the given constant levels for its whole length.
///
/// [beatPeriodMs] of 0 means no beat grid at all — the ambient case, where the
/// bars should still follow the bands.
BeatMap bandMap({
  required List<double> levels,
  int durationMs = 4000,
  int beatPeriodMs = 500,
}) {
  final stride = BeatBand.values.length;
  final frames = (durationMs / 1000 * BeatMap.bandFps).ceil();
  final bands = Uint8List(frames * stride);
  for (var frame = 0; frame < frames; frame++) {
    for (var b = 0; b < stride; b++) {
      bands[frame * stride + b] = (levels[b] * 255).round();
    }
  }

  final beatCount = beatPeriodMs == 0 ? 0 : (durationMs / beatPeriodMs).floor();
  final beatsMs = Int32List(beatCount);
  final strengths = Float32List(beatCount);
  final downbeats = Uint8List(beatCount);
  for (var i = 0; i < beatCount; i++) {
    beatsMs[i] = i * beatPeriodMs;
    strengths[i] = 1.0;
    downbeats[i] = i % 4 == 0 ? 1 : 0;
  }

  return BeatMap(
    version: BeatMap.currentVersion,
    durationMs: durationMs,
    bpm: beatPeriodMs == 0 ? 0 : 60000 / beatPeriodMs,
    beatsMs: beatsMs,
    beatStrength: strengths,
    downbeats: downbeats,
    bands: bands,
  );
}

void main() {
  group('ballistics', () {
    test('one time constant covers ~63% of the distance', () {
      final level = SpectrumBars.advance(0, 1, SpectrumBars.attackTau);
      expect(level, closeTo(0.632, 0.005));
    });

    test('bars rise faster than they fall', () {
      const dt = 1 / 60;
      final rise = SpectrumBars.advance(0.2, 0.8, dt) - 0.2;
      final fall = 0.8 - SpectrumBars.advance(0.8, 0.2, dt);
      expect(rise, greaterThan(fall));
    });

    test('is frame-rate independent', () {
      // Two steps at 120 Hz must land where one step at 60 Hz does, or the
      // visualiser is a different animation on every phone.
      const slow = 1 / 60;
      const fast = 1 / 120;
      final oneStep = SpectrumBars.advance(0.1, 0.9, slow);
      var twoSteps = SpectrumBars.advance(0.1, 0.9, fast);
      twoSteps = SpectrumBars.advance(twoSteps, 0.9, fast);
      expect(twoSteps, closeTo(oneStep, 1e-9));
    });

    test('a zero-length frame moves nothing', () {
      expect(SpectrumBars.advance(0.4, 1.0, 0), 0.4);
    });

    // The two guards below are what stopped this from being "too smoothed
    // out". Scored against real audio (a dense hardstyle track and a sparse
    // vocal one), the original 45/190ms pair left 51% of the bass onsets in
    // the dense track producing no visible rise, with a 83ms lag. Slowing
    // these constants back down is what that regression looks like.
    test('a hit is visible in the frame it lands', () {
      final afterOneFrame =
          SpectrumBars.advance(SpectrumBars.floor, 1.0, 1 / 60);
      expect(afterOneFrame - SpectrumBars.floor, greaterThan(0.5));
    });

    test('a bar is most of the way down within a beat', () {
      // 150ms is well inside a beat at any sane tempo. A bar still holding
      // most of its height there is a bar that cannot show the next hit.
      var level = 1.0;
      for (var i = 0; i < 9; i++) {
        level = SpectrumBars.advance(level, SpectrumBars.floor, 1 / 60);
      }
      expect(level - SpectrumBars.floor, lessThan(0.1));
    });
  });

  group('shaping', () {
    test('silence still leaves a visible bar', () {
      expect(SpectrumBars.shape(0), SpectrumBars.floor);
    });

    test('full energy reaches the top and nothing exceeds it', () {
      expect(SpectrumBars.shape(1), closeTo(1.0, 1e-9));
      expect(SpectrumBars.shape(4), closeTo(1.0, 1e-9));
    });

    test('is monotonic across the range', () {
      var previous = -1.0;
      for (var i = 0; i <= 20; i++) {
        final value = SpectrumBars.shape(i / 20);
        expect(value, greaterThan(previous));
        expect(value, inInclusiveRange(SpectrumBars.floor, 1.0));
        previous = value;
      }
    });
  });

  group('beat punch', () {
    test('peaks shortly after the beat, not on it', () {
      // The rise time is physical: something struck takes ~18ms to reach full
      // deflection. A punch that peaks at t=0 is a light switch.
      final atBeat = SpectrumBars.punch(0, 500);
      final justAfter = SpectrumBars.punch(20, 500);
      expect(atBeat, lessThan(justAfter));
      expect(justAfter, greaterThan(0.85));
      expect(SpectrumBars.punch(40, 500), closeTo(1.0, 0.01));
    });

    test('has faded by the time the next beat arrives', () {
      // Not quite zero, but far enough down that successive punches read as
      // separate hits instead of stacking onto a raised plateau.
      expect(SpectrumBars.punch(500, 500), lessThan(0.08));
    });

    test('never fires before the beat', () {
      expect(SpectrumBars.punch(-10, 500), 0);
    });

    test('keeps its shape across tempos', () {
      // Same proportion of the beat elapsed at 70 and 180 BPM should leave the
      // punch in roughly the same place, which is what stops fast tracks from
      // reading as one smeared plateau.
      final slow = SpectrumBars.punch(857 * 0.4, 857);
      final fast = SpectrumBars.punch(333 * 0.4, 333);
      expect((slow - fast).abs(), lessThan(0.25));
    });
  });

  group('band to bar mapping', () {
    test('left is bass and right is treble', () {
      final map = bandMap(levels: const [1.0, 0.0, 0.0, 0.0], beatPeriodMs: 0);
      final out = List<double>.filled(SpectrumBars.barCount, 0);

      expect(SpectrumBars.targetsAt(map, 1000, out), isTrue);
      expect(out[0], closeTo(1.0, 0.01));
      expect(out[1], SpectrumBars.floor);
      expect(out[2], SpectrumBars.floor);
      expect(out[3], SpectrumBars.floor);

      final treble =
          bandMap(levels: const [0.0, 0.0, 0.0, 1.0], beatPeriodMs: 0);
      expect(SpectrumBars.targetsAt(treble, 1000, out), isTrue);
      expect(out[3], closeTo(1.0, 0.01));
      expect(out[0], SpectrumBars.floor);
    });

    test('the beat punches the low bars only', () {
      final map = bandMap(levels: const [0.3, 0.3, 0.3, 0.3]);
      final out = List<double>.filled(SpectrumBars.barCount, 0);

      // Late in the beat, with the previous punch nearly gone.
      SpectrumBars.targetsAt(map, 1490, out);
      final before = List<double>.from(out);

      // Just after the next one, the low end has pulled ahead.
      SpectrumBars.targetsAt(map, 1520, out);
      expect(out[0] - before[0], greaterThan(0.1));
      expect(out[1] - before[1], greaterThan(0.04));
      // Bass moves more than low-mid: a beat is felt at the bottom.
      expect(out[0] - before[0], greaterThan(out[1] - before[1]));
      // Mid and air are the bands a beat does not live in, and the grid must
      // not push them around — that is what makes four bars read as four
      // bands rather than one signal copied four times.
      expect(out[2], closeTo(before[2], 1e-9));
      expect(out[3], closeTo(before[3], 1e-9));
    });

    test('a beatless track still follows its bands', () {
      // Ambient and spoken word never get a grid. They keep their envelopes,
      // and that is enough to drive the bars.
      final map = bandMap(levels: const [0.8, 0.5, 0.2, 0.1], beatPeriodMs: 0);
      final out = List<double>.filled(SpectrumBars.barCount, 0);

      expect(map.hasBeats, isFalse);
      expect(SpectrumBars.targetsAt(map, 1000, out), isTrue);
      expect(out[0], greaterThan(out[1]));
      expect(out[1], greaterThan(out[2]));
      expect(out[2], greaterThan(out[3]));
    });

    test('an empty map reports no usable bands', () {
      final out = List<double>.filled(SpectrumBars.barCount, 0);
      expect(SpectrumBars.targetsAt(BeatMap.empty(), 0, out), isFalse);
    });
  });

  group('controller', () {
    test('drives the bars toward the bands of the current track', () {
      final controller = SpectrumController.forTesting()
        ..debugSetMode(VisualizerMode.synced)
        ..debugBeatMap = bandMap(levels: const [1.0, 0.0, 0.0, 0.0]);

      for (var i = 0; i < 120; i++) {
        controller.advance(1 / 60, 1000 + i * (1000 / 60));
      }

      expect(controller.levels[0], greaterThan(0.7));
      expect(controller.levels[3], lessThan(0.3));
      expect(controller.debugGridBlend, 1.0);
    });

    test('runs the idle walk until a beat map arrives', () {
      final controller = SpectrumController.forTesting()
        ..debugSetMode(VisualizerMode.synced);

      for (var i = 0; i < 60; i++) {
        controller.advance(1 / 60, i * (1000 / 60));
      }

      expect(controller.debugGridBlend, 0);
      expect(controller.isSynced, isFalse);
      // Still moving, just not to anything in particular.
      expect(
        controller.levels.any((level) => level > SpectrumBars.floor),
        isTrue,
      );
    });

    test('classic mode ignores the beat map entirely', () {
      final controller = SpectrumController.forTesting()
        ..debugSetMode(VisualizerMode.classic)
        ..debugBeatMap = bandMap(levels: const [1.0, 0.0, 0.0, 0.0]);

      for (var i = 0; i < 120; i++) {
        controller.advance(1 / 60, 1000 + i * (1000 / 60));
      }

      expect(controller.debugGridBlend, 0);
    });

    test('hands over to the grid gradually rather than jumping', () {
      final controller = SpectrumController.forTesting()
        ..debugSetMode(VisualizerMode.synced);

      controller.advance(1 / 60, 0);
      controller.debugBeatMap = bandMap(levels: const [1.0, 1.0, 1.0, 1.0]);
      controller.advance(1 / 60, 1000);

      // One frame in, the grid is only just starting to take over.
      expect(controller.debugGridBlend, greaterThan(0));
      expect(controller.debugGridBlend, lessThan(0.2));
    });

    test('stays silent until something is watching', () {
      final controller = SpectrumController.forTesting();
      expect(controller.debugWired, isFalse);
      expect(controller.debugTicking, isFalse);

      void listener() {}
      controller.addListener(listener);
      // Detached from a player, so it still cannot wire up — but the levels
      // stay at rest either way, which is what a bar-less screen renders.
      expect(controller.debugTicking, isFalse);
      controller.removeListener(listener);

      for (final level in controller.levels) {
        expect(level, SpectrumBars.floor);
      }
    });
  });
}

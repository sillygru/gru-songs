import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/presentation/widgets/beat_particle_field.dart';
import 'package:wispie/presentation/widgets/player_motion.dart';

import 'player_motion_test.dart' show gridMap;

/// Measures whether the particle field's *travel* is driven by the music, and
/// whether the motes stay where the listener can see them.
///
/// The rest of the field's behaviour is covered in `player_motion_widget_test`;
/// these are the two properties a listener actually complained about, so they
/// get numbers rather than adjectives. Every metric here is a share or a ratio,
/// with a stated value for a field that ignores the music entirely — so a
/// regression reads as "back to 0.5" rather than as an unfamiliar constant
/// drifting.
const _phoneAspect = 1080 / 2340;

/// Runs [seconds] of a 120 BPM grid at 60fps and reports where the motion went.
///
/// Positions are sampled through [ParticleSystem.displacedPosition], i.e. what
/// is actually drawn, and per-frame deltas are accumulated so the toroidal wrap
/// does not register as a jump across the screen.
({
  double beatShare,
  double speedRatio,
  double retention,
  double spread,
}) profile({
  double seconds = 120,
  PlayerMotionIntensity intensity = PlayerMotionIntensity.bold,
  int periodMs = 500,
}) {
  final beats = (seconds * 1000 / periodMs).ceil() + 4;
  final controller = PlayerMotionController.forTesting()
    ..beatMap = gridMap(beats: beats, periodMs: periodMs);
  addTearDown(controller.dispose);

  final system = ParticleSystem();
  final spec = MotionIntensitySpec.of(intensity);

  final previous = <Particle, Offset>{};

  // Travel inside the first 250ms after a beat versus the rest of the beat.
  var onBeatPath = 0.0;
  var offBeatPath = 0.0;
  // Mean speed just after a beat versus just before the next one.
  var afterSpeed = 0.0;
  var afterSamples = 0;
  var beforeSpeed = 0.0;
  var beforeSamples = 0;
  // Share of samples a mote spends inside the visible box.
  var onScreen = 0;
  var samples = 0;
  // Occupancy of a 3x3 grid over the visible box, summed across the run.
  final buckets = List<int>.filled(9, 0);

  final frames = (seconds * 60).round();
  for (var frame = 0; frame <= frames; frame++) {
    final ms = frame * 1000 / 60;
    system.update(
      elapsedSeconds: ms / 1000,
      frame: controller.computeFrame(ms),
      spec: spec,
      aspect: _phoneAspect,
    );

    final sinceBeat = ms % periodMs;
    final toNextBeat = periodMs - sinceBeat;
    // Ignore the first beat: the field is still settling out of its spawn.
    final counted = ms >= periodMs;

    for (final particle in system.particles) {
      final position = system.displacedPosition(particle);
      final last = previous[particle];
      previous[particle] = position;
      if (!counted || last == null) continue;

      final step = position - last;
      // Only a wrap moves a mote half the screen in a frame; it breaks the
      // track rather than counting as travel.
      if (step.dx.abs() > 0.5 || step.dy.abs() > 0.5) continue;

      final distance = step.distance;
      if (sinceBeat < 250) {
        onBeatPath += distance;
      } else {
        offBeatPath += distance;
      }

      if (sinceBeat < 120) {
        afterSpeed += distance;
        afterSamples++;
      } else if (toNextBeat <= 120) {
        beforeSpeed += distance;
        beforeSamples++;
      }

      samples++;
      if (position.dx >= 0 &&
          position.dx <= 1 &&
          position.dy >= 0 &&
          position.dy <= 1) {
        onScreen++;
        final cx = (position.dx * 3).clamp(0, 2).toInt();
        final cy = (position.dy * 3).clamp(0, 2).toInt();
        buckets[cy * 3 + cx]++;
      }
    }
  }

  final busiest = buckets.reduce(math.max);
  final quietest = buckets.reduce(math.min);

  return (
    beatShare: onBeatPath / (onBeatPath + offBeatPath),
    speedRatio: (afterSpeed / afterSamples) / (beforeSpeed / beforeSamples),
    retention: onScreen / samples,
    spread: quietest == 0 ? double.infinity : busiest / quietest,
  );
}

void main() {
  group('the beat is what moves the field', () {
    // The first 250ms after a beat is half of a 120 BPM beat, so a field whose
    // travel has nothing to do with the music scores exactly 0.5 here — and the
    // implementation this replaced measured 0.495 (bold) and 0.504 (subtle),
    // which is the complaint stated as a number.
    test('most travel happens in the half of the beat right after it', () {
      expect(profile().beatShare, greaterThan(0.65));
      expect(
        profile(intensity: PlayerMotionIntensity.subtle).beatShare,
        greaterThan(0.62),
        reason:
            'a calmer setting should still be visibly in time, just gentler',
      );
    });

    // Speed just after a beat against speed just before the next one. The
    // implementation this replaced measured 0.98 and 1.01 — no contrast at all.
    test('the field surges on the beat and coasts between', () {
      expect(profile().speedRatio, greaterThan(2.5));
      expect(
        profile(intensity: PlayerMotionIntensity.subtle).speedRatio,
        greaterThan(2.0),
      );
    });

    test('a stronger setting is more beat-driven than a quieter one', () {
      expect(
        profile(intensity: PlayerMotionIntensity.subtle).speedRatio,
        lessThan(profile().speedRatio),
      );
    });
  });

  group('the field stays where it can be seen', () {
    test('motes are on screen most of the time, but do still leave', () {
      // The implementation this replaced left a mote off screen 26% of the
      // time: nothing pulled it back, and its entire exit fade happened outside
      // the visible box. Both bounds matter — pinning this to 1.0 would mean
      // the inward bias had become a wall, and a field that can never leave
      // reads as trapped rather than as drifting.
      for (final intensity in PlayerMotionIntensity.values) {
        final retention = profile(intensity: intensity).retention;
        expect(retention, greaterThan(0.85), reason: intensity.name);
        expect(retention, lessThan(0.99), reason: intensity.name);
      }
    });

    test('no part of the screen is left empty', () {
      // A loose sanity bound, not a precision instrument. A mote sits in one
      // ninth of the screen for seconds at a time, so the effective independent
      // sample count per bucket is low and max/min over nine buckets lands near
      // 1.5 even for a perfectly uniform field. This catches a flow field that
      // genuinely strands a region; it cannot resolve small differences in
      // uniformity, and should not be read as if it could.
      for (final intensity in PlayerMotionIntensity.values) {
        expect(profile(intensity: intensity).spread, lessThan(4.0),
            reason: intensity.name);
      }
    });
  });
}

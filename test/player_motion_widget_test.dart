import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/beat_map.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/presentation/widgets/beat_cover_glow.dart';
import 'package:wispie/presentation/widgets/beat_particle_field.dart';
import 'package:wispie/presentation/widgets/beat_reactive_cover.dart';
import 'package:wispie/presentation/widgets/player_motion.dart';

import 'player_motion_test.dart' show gridMap;

/// [gridMap]'s bands with the beat grid taken away, so a run driven by this
/// differs from one driven by [gridMap] *only* in the beat force.
BeatMap beatlessMap({int beats = 16, int periodMs = 500}) {
  final frames = (beats * periodMs / 1000 * BeatMap.bandFps).ceil();
  return BeatMap(
    version: BeatMap.currentVersion,
    durationMs: beats * periodMs,
    bpm: 0,
    beatsMs: Int32List(0),
    beatStrength: Float32List(0),
    downbeats: Uint8List(0),
    bands: Uint8List(frames * BeatBand.values.length)
      ..fillRange(0, frames * BeatBand.values.length, 128),
  );
}

/// Steps [controller] across [beats] beats of a 120 BPM grid, pumping a frame
/// every ~16ms so the render paths are exercised the way a real ticker would.
Future<void> playThrough(
  WidgetTester tester,
  PlayerMotionController controller, {
  int beats = 3,
}) async {
  final totalMs = beats * 500;
  for (var ms = 0; ms < totalMs; ms += 16) {
    controller.debugTick(Duration(milliseconds: ms), ms.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget host(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 300, height: 600, child: child)),
  );
}

void main() {
  group('BeatReactiveCover', () {
    testWidgets('passes the artwork straight through when disabled',
        (tester) async {
      final controller = PlayerMotionController.forTesting();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatReactiveCover(
          controller: controller,
          enabled: false,
          child: const SizedBox(key: Key('art'), width: 200, height: 200),
        ),
      ));

      expect(find.byKey(const Key('art')), findsOneWidget);
      // No transform layer at all when off — the cover must be untouched.
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('scales the artwork across a beat without throwing',
        (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatReactiveCover(
          controller: controller,
          enabled: true,
          child: const SizedBox(key: Key('art'), width: 200, height: 200),
        ),
      ));

      double scaleNow() {
        final transform = tester.widget<Transform>(
          find
              .ancestor(
                of: find.byKey(const Key('art')),
                matching: find.byType(Transform),
              )
              .first,
        );
        // Read the x scale directly. getMaxScaleOnAxis() would report the
        // untouched z axis as 1.0 and hide every contraction below 1.
        return transform.transform.entry(0, 0);
      }

      // Just before beat 4 (2000ms) the anticipation dip should have it under 1.
      controller.debugTick(const Duration(milliseconds: 1980), 1980);
      await tester.pump();
      final anticipating = scaleNow();

      // Just after, the punch should have it above 1.
      controller.debugTick(const Duration(milliseconds: 2044), 2044);
      await tester.pump();
      final punching = scaleNow();

      expect(anticipating, lessThan(1.0));
      expect(punching, greaterThan(1.0));
      expect(punching, lessThan(1.06), reason: 'subtle must stay subtle');
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a full run of beats', (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatReactiveCover(
          controller: controller,
          enabled: true,
          child: const SizedBox(width: 200, height: 200),
        ),
      ));

      await playThrough(tester, controller);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never leaves the artwork visibly resized', (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatReactiveCover(
          controller: controller,
          enabled: true,
          child: const SizedBox(key: Key('art'), width: 200, height: 200),
        ),
      ));

      // The overshoot and the lean are additions to the gesture, not licence
      // for the cover to wander off its own size.
      var minimum = double.infinity;
      var maximum = double.negativeInfinity;
      for (var ms = 0; ms < 4000; ms += 8) {
        controller.debugTick(Duration(milliseconds: ms), ms.toDouble());
        await tester.pump();
        final scale = tester
            .widget<Transform>(
              find
                  .ancestor(
                    of: find.byKey(const Key('art')),
                    matching: find.byType(Transform),
                  )
                  .first,
            )
            .transform
            .entry(0, 0);
        minimum = scale < minimum ? scale : minimum;
        maximum = scale > maximum ? scale : maximum;
      }

      expect(minimum, greaterThan(0.98));
      expect(maximum, lessThan(1.05));
      // ...and it does actually move.
      expect(maximum - minimum, greaterThan(0.01));
    });
  });

  group('animation clock', () {
    testWidgets('does not rewind when playback pauses and resumes',
        (tester) async {
      // Every particle's drift phase is a function of this clock. A ticker
      // restarts its elapsed from zero, so if that leaked through, the whole
      // field would snap back into step on every resume — which is exactly what
      // it used to do.
      final controller = PlayerMotionController.forTesting();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(const SizedBox()));
      controller.attach(tester);

      controller.debugSetPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final beforePause = controller.elapsed;
      expect(beforePause, greaterThan(Duration.zero));

      controller.debugSetPlaying(false);
      await tester.pump(const Duration(milliseconds: 200));
      controller.debugSetPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.elapsed, greaterThan(beforePause));

      // The ticker has to be idle before the body ends: the framework checks
      // for stray tickers before tear-downs run.
      controller.debugSetPlaying(false);
    });
  });

  group('BeatParticleField', () {
    testWidgets('paints across several beats without throwing', (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatParticleField(
          controller: controller,
          accent: const Color(0xFF6C8CFF),
        ),
      ));

      // Covers the interesting branches: shockwave spawn on each beat, the
      // refraction split while pulse is high, and wave expiry in between.
      await playThrough(tester, controller, beats: 5);

      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a beatless map', (tester) async {
      final controller = PlayerMotionController.forTesting();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(
        BeatParticleField(
          controller: controller,
          accent: const Color(0xFF6C8CFF),
        ),
      ));

      await playThrough(tester, controller, beats: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a degenerate zero-size box', (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 0,
            height: 0,
            child: BeatParticleField(
              controller: controller,
              accent: const Color(0xFF6C8CFF),
            ),
          ),
        ),
      ));

      await playThrough(tester, controller, beats: 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not intercept touches', (tester) async {
      final controller = PlayerMotionController.forTesting();
      addTearDown(controller.dispose);

      var tapped = false;
      await tester.pumpWidget(host(
        Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped = true,
              ),
            ),
            Positioned.fill(
              child: BeatParticleField(
                controller: controller,
                accent: const Color(0xFF6C8CFF),
              ),
            ),
          ],
        ),
      ));

      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue,
          reason: 'the particle layer sits over the whole player screen and '
              'must never swallow input');
    });
  });

  group('BeatCoverGlow', () {
    final shellKey = GlobalKey();
    final coverKey = GlobalKey();

    /// A stand-in for the player shell: a full-bleed glow layer under a cover
    /// placed at [coverLeft], or no cover at all.
    Widget glowHost(
      PlayerMotionController controller, {
      double? coverLeft = 50,
    }) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: Stack(
              key: shellKey,
              children: [
                Positioned.fill(
                  child: BeatCoverGlow(
                    controller: controller,
                    coverKey: coverKey,
                    shellKey: shellKey,
                    accent: const Color(0xFF6C8CFF),
                  ),
                ),
                if (coverLeft != null)
                  Positioned(
                    left: coverLeft,
                    top: 100,
                    width: 200,
                    height: 200,
                    child: SizedBox(key: coverKey),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('spills past the artwork it lights up', (tester) async {
      // The whole point of hoisting the glow out of the pane: it has to be
      // bigger than the cover, and it has to be free to paint outside it.
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(glowHost(controller));

      controller.debugTick(const Duration(milliseconds: 2044), 2044);
      await tester.pump();

      expect(
        find.byType(BeatCoverGlow),
        paints
          ..something((symbol, arguments) {
            if (symbol != #drawRRect) return false;
            final rrect = arguments.first as RRect;
            // The 200x200 cover sits at (50, 100) in the shell.
            return rrect.outerRect.overlaps(
                  const Rect.fromLTWH(50, 100, 200, 200),
                ) &&
                rrect.width > 200 &&
                rrect.height > 200;
          }),
      );
    });

    testWidgets('stays dark before the first beat lands', (tester) async {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(glowHost(controller));

      controller.debugTick(Duration.zero, -400);
      await tester.pump();

      expect(find.byType(BeatCoverGlow), paintsNothing);
    });

    testWidgets('paints nothing when the artwork is not on screen',
        (tester) async {
      // Video mode, or a pane that was never built.
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(glowHost(controller, coverLeft: null));

      controller.debugTick(const Duration(milliseconds: 2044), 2044);
      await tester.pump();

      expect(find.byType(BeatCoverGlow), paintsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fades out once the cover has been swiped away',
        (tester) async {
      // The cover is a page over on Lyrics and Queue; a glow with no visible
      // source reads as a leak at the screen edge.
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(glowHost(controller, coverLeft: -300));

      controller.debugTick(const Duration(milliseconds: 2044), 2044);
      await tester.pump();

      expect(find.byType(BeatCoverGlow), paintsNothing);
    });
  });

  group('particle simulation', () {
    /// Runs a minute of playback at 60fps against [map] and reports the mean
    /// distance of every particle from the field's centre.
    double meanRadiusAfterAMinute(BeatMap map) {
      final controller = PlayerMotionController.forTesting()..beatMap = map;
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);

      for (var frame = 0; frame <= 3600; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );
      }

      var total = 0.0;
      for (final particle in system.particles) {
        final position = system.displacedPosition(particle);
        final dx = position.dx - 0.5;
        final dy = position.dy - 0.44;
        total += math.sqrt(dx * dx + dy * dy);
      }
      return total / system.particles.length;
    }

    test('beats do not push the field off screen', () {
      // The original bug: each beat added a permanent outward velocity, so the
      // whole field streamed away from the centre and left. The two runs differ
      // only in whether there is a beat grid, so any spread between them is the
      // beat force failing to give back what it took.
      final withBeats = meanRadiusAfterAMinute(gridMap(beats: 200));
      final withoutBeats = meanRadiusAfterAMinute(beatlessMap(beats: 200));

      expect(withBeats, closeTo(withoutBeats, 0.02));
    });

    test('the beat displacement stays bounded and returns to rest', () {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap(beats: 40);
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);
      var peak = 0.0;

      for (var frame = 0; frame <= 1200; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );
        for (final particle in system.particles) {
          peak = math.max(peak, particle.push.abs());
        }
      }

      // It moves...
      expect(peak, greaterThan(0.005));
      // ...without any particle being flung across the screen.
      expect(peak, lessThan(0.13));

      // Once the music stops, the spring puts everything back.
      for (var frame = 1201; frame <= 1400; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: BeatFrame.idle,
          spec: spec,
        );
      }
      for (final particle in system.particles) {
        expect(particle.push.abs(), lessThan(0.001));
      }
    });

    test('particles do not all answer a beat by the same amount', () {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap();
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);
      for (var frame = 0; frame <= 120; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );
      }

      final moved =
          system.particles.where((p) => p.push.abs() > 1e-6).map((p) => p.push);
      expect(moved.length, greaterThan(2));
      expect(moved.toSet().length, moved.length,
          reason: 'a field that moves in unison reads as one object');
    });

    /// Runs [seconds] of playback at 60fps and reports, per particle, how far it
    /// actually went.
    ///
    /// Motion is accumulated from per-frame deltas rather than measured between
    /// start and end positions, so the toroidal wrap does not read as a jump
    /// backwards — `net` is displacement in the unwrapped plane. Particles are
    /// keyed by identity, so a mote that reaches the end of its life and is
    /// recycled starts a fresh track instead of registering as a teleport.
    ///
    /// Only the first generation is reported, and [seconds] is kept under the
    /// shortest possible lifetime, so every mote is measured over the whole
    /// window.
    ({double meanPath, double meanNet, double reversals}) travelOver(
      double seconds, {
      PlayerMotionIntensity intensity = PlayerMotionIntensity.bold,
    }) {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap(beats: 200);
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(intensity);

      final path = <Particle, double>{};
      final netX = <Particle, double>{};
      final netY = <Particle, double>{};
      final previous = <Particle, Offset>{};
      final previousStep = <Particle, Offset>{};
      var reversals = 0;
      var steps = 0;

      for (var frame = 0; frame <= (seconds * 60).round(); frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );

        for (final particle in system.particles) {
          final position = system.displacedPosition(particle);
          final last = previous[particle];
          if (last != null) {
            final step = position - last;
            // A wrap is the only way a mote covers half the screen in one
            // frame; it breaks the track rather than contributing to it.
            if (step.dx.abs() < 0.5 && step.dy.abs() < 0.5) {
              path[particle] = (path[particle] ?? 0) + step.distance;
              netX[particle] = (netX[particle] ?? 0) + step.dx;
              netY[particle] = (netY[particle] ?? 0) + step.dy;

              final lastStep = previousStep[particle];
              if (lastStep != null) {
                steps++;
                if (step.dx * lastStep.dx + step.dy * lastStep.dy < 0) {
                  reversals++;
                }
              }
              previousStep[particle] = step;
            } else {
              previousStep.remove(particle);
            }
          }
          previous[particle] = position;
        }
      }

      final firstGeneration = path.keys.where((p) => p.bornAt == 0).toList();
      var totalPath = 0.0;
      var totalNet = 0.0;
      for (final particle in firstGeneration) {
        final nx = netX[particle] ?? 0;
        final ny = netY[particle] ?? 0;
        totalPath += path[particle]!;
        totalNet += math.sqrt(nx * nx + ny * ny);
      }

      return (
        meanPath: totalPath / firstGeneration.length,
        meanNet: totalNet / firstGeneration.length,
        reversals: reversals / steps,
      );
    }

    test('motes travel instead of hovering around where they spawned', () {
      // The bug this guards: driving position from a sinusoidal *velocity*
      // integrates to an oscillation about two percent of the screen wide, so
      // the field wobbled in place. Net displacement is what catches it —
      // path length alone does not, because per-frame noise inflates it while
      // going nowhere.
      final travel = travelOver(12);

      expect(travel.meanNet, greaterThan(0.25),
          reason: 'over twelve seconds a mote should end up somewhere else, '
              'not back where it started');
      expect(travel.meanPath, greaterThan(0.5));
    });

    test('quieter intensities travel less, but still travel', () {
      final subtle = travelOver(12, intensity: PlayerMotionIntensity.subtle);
      final bold = travelOver(12, intensity: PlayerMotionIntensity.bold);

      expect(subtle.meanNet, lessThan(bold.meanNet));
      expect(subtle.meanNet, greaterThan(0.12));
    });

    test('the field flows rather than vibrating', () {
      // Direction reversals are the signature of the per-frame white noise this
      // replaced: uncorrelated jitter turns around on roughly half of all
      // frames, while something genuinely travelling almost never does.
      final travel = travelOver(12);

      expect(travel.reversals, lessThan(0.05),
          reason: 'motes should hold a heading between frames');
    });

    test('the beat stops turning the field once the music stops', () {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap(beats: 200);
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);

      var peak = 0.0;
      for (var frame = 0; frame <= 1800; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );
        for (final particle in system.particles) {
          peak = math.max(peak, particle.swirlVelocity.abs());
        }
      }

      // Beats visibly turn the field...
      expect(peak, greaterThan(0.03));
      // ...without ever winding a mote up into a spin.
      expect(peak, lessThan(0.45));

      for (var frame = 1801; frame <= 2100; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: BeatFrame.idle,
          spec: spec,
        );
      }
      for (final particle in system.particles) {
        expect(particle.swirlVelocity.abs(), lessThan(0.001));
      }
    });

    test('travel never empties the screen', () {
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap(beats: 300);
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);
      for (var frame = 0; frame <= 60 * 120; frame++) {
        final ms = frame * 1000 / 60;
        system.update(
          elapsedSeconds: ms / 1000,
          frame: controller.computeFrame(ms),
          spec: spec,
        );
      }

      final onScreen = system.particles
          .where((p) => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1)
          .length;
      expect(onScreen / system.particles.length, greaterThan(0.6),
          reason: 'after two minutes of travel most of the field should still '
              'be somewhere the listener can see it');
    });

    test('a quiet beat stirs only part of the field', () {
      // Two-second beats, so one wavefront has finished crossing the field
      // before the next one is spawned and the two cannot be confused.
      final controller = PlayerMotionController.forTesting()
        ..beatMap = gridMap(beats: 8, periodMs: 2000);
      addTearDown(controller.dispose);

      final system = ParticleSystem();
      final spec = MotionIntensitySpec.of(PlayerMotionIntensity.bold);
      final excited = <Particle>{};
      final last = <Particle, double>{};

      /// Counts the motes whose flare *rises* during the window. Testing for a
      /// non-zero flare instead would count everything, since the previous
      /// beat's flare is still decaying.
      int recruitedBetween(double fromMs, double toMs) {
        excited.clear();
        for (var frame = (fromMs / 1000 * 60).round();
            frame <= (toMs / 1000 * 60).round();
            frame++) {
          final ms = frame * 1000 / 60;
          system.update(
            elapsedSeconds: ms / 1000,
            frame: controller.computeFrame(ms),
            spec: spec,
          );
          for (final particle in system.particles) {
            if (particle.excitation > (last[particle] ?? 0) + 1e-9) {
              excited.add(particle);
            }
            last[particle] = particle.excitation;
          }
        }
        return excited.length;
      }

      // gridMap makes every fourth beat a downbeat, so 0ms lands full strength
      // and 2000ms lands at the offbeat level.
      final byDownbeat = recruitedBetween(0, 1900);
      final byOffbeat = recruitedBetween(1901, 3900);

      expect(byDownbeat, system.particles.length,
          reason: 'a full-strength beat should reach the whole field');
      expect(byOffbeat, greaterThan(0));
      expect(byOffbeat, lessThan(byDownbeat),
          reason: 'a quieter beat should pass straight through the motes that '
              'are not listening for it — a field where every mote answers '
              'every beat reads as one object being triggered');
    });
  });
}

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
  });
}

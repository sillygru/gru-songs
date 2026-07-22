import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/widgets/beat_particle_field.dart';
import 'package:wispie/presentation/widgets/beat_reactive_cover.dart';
import 'package:wispie/presentation/widgets/player_motion.dart';

import 'player_motion_test.dart' show gridMap;

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
          accent: const Color(0xFF6C8CFF),
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
          accent: const Color(0xFF6C8CFF),
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
          accent: const Color(0xFF6C8CFF),
          enabled: true,
          child: const SizedBox(width: 200, height: 200),
        ),
      ));

      await playThrough(tester, controller);
      expect(tester.takeException(), isNull);
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
}

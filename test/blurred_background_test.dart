import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/widgets/blurred_background.dart';

double _extractRotationAngle(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(find.byType(Transform));
  for (final transform in transforms) {
    final storage = transform.transform.storage;
    final cosVal = storage[0];
    final sinVal = storage[1];
    if ((cosVal * cosVal + sinVal * sinVal - 1.0).abs() < 1e-4) {
      var angle = math.atan2(sinVal, cosVal);
      if (angle < 0) angle += 2 * math.pi;
      return angle;
    }
  }
  return 0.0;
}

void main() {
  testWidgets('BlurredBackground starts at 0 rotation when slowSpin is false',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 800,
          child: BlurredBackground(
            url: '',
            slowSpin: false,
          ),
        ),
      ),
    );

    expect(_extractRotationAngle(tester), 0.0);
  });

  testWidgets('BlurredBackground rotates clockwise when slowSpin is true',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 800,
          child: BlurredBackground(
            url: '',
            slowSpin: true,
          ),
        ),
      ),
    );

    final initialAngle = _extractRotationAngle(tester);
    expect(initialAngle, 0.0);

    await tester.pump(const Duration(seconds: 5));
    final angleAfter5s = _extractRotationAngle(tester);
    expect(angleAfter5s, greaterThan(initialAngle));
  });

  testWidgets(
      'BlurredBackground stops at current position on pause and resumes from same position on unpause',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 800,
          child: BlurredBackground(
            url: '',
            slowSpin: true,
          ),
        ),
      ),
    );

    // Spin for 15 seconds
    await tester.pump(const Duration(seconds: 15));
    final angleAtPause = _extractRotationAngle(tester);
    expect(angleAtPause, greaterThan(0.5));

    // Pause playback
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 800,
          child: BlurredBackground(
            url: '',
            slowSpin: false,
          ),
        ),
      ),
    );

    // Angle must stay exactly at angleAtPause when paused
    await tester.pump(const Duration(seconds: 3));
    final angleWhilePaused = _extractRotationAngle(tester);
    expect((angleWhilePaused - angleAtPause).abs(), lessThan(1e-4));

    // Unpause playback
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 800,
          child: BlurredBackground(
            url: '',
            slowSpin: true,
          ),
        ),
      ),
    );

    // Immediately after unpausing, angle is still at angleAtPause
    final angleImmediatelyAfterUnpause = _extractRotationAngle(tester);
    expect(
      (angleImmediatelyAfterUnpause - angleAtPause).abs(),
      lessThan(1e-4),
    );

    // Then continues spinning forward clockwise
    await tester.pump(const Duration(seconds: 3));
    final angleAfterSpinning = _extractRotationAngle(tester);
    expect(angleAfterSpinning, greaterThan(angleAtPause));
  });
}

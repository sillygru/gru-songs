import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/components/pressable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pressable hold and tap gestures', () {
    testWidgets(
        'short tap triggers onTap and does not trigger long press callbacks',
        (tester) async {
      var tapCount = 0;
      var longPressStartCount = 0;
      var longPressEndCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () => tapCount++,
                onLongPressStart: (_) => longPressStartCount++,
                onLongPressEnd: (_) => longPressEndCount++,
                child: const Text('Skip'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(tapCount, equals(1));
      expect(longPressStartCount, equals(0));
      expect(longPressEndCount, equals(0));
    });

    testWidgets(
        'long press hold triggers onLongPressStart and onLongPressEnd without triggering onTap',
        (tester) async {
      var tapCount = 0;
      var longPressStartCount = 0;
      var longPressEndCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () => tapCount++,
                onLongPressStart: (_) => longPressStartCount++,
                onLongPressEnd: (_) => longPressEndCount++,
                child: const Text('Skip'),
              ),
            ),
          ),
        ),
      );

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Skip')));
      // Advance past standard long-press timeout (500ms)
      await tester.pump(const Duration(milliseconds: 600));

      expect(longPressStartCount, equals(1));
      expect(tapCount, equals(0));

      // Release finger
      await gesture.up();
      await tester.pumpAndSettle();

      expect(longPressEndCount, equals(1));
      expect(tapCount, equals(0)); // Tap must NOT fire after long press
    });
  });
}

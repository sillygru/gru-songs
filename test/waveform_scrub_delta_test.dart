import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/presentation/widgets/waveform_progress_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'scrubbing waveform lowers time labels and displays delta in seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: WaveformProgressBar(
                  filename: 'test_song.mp3',
                  path: '/path/test_song.mp3',
                  progress: const Duration(seconds: 30),
                  total: const Duration(seconds: 120),
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final waveformFinder = find.byType(WaveformProgressBar);
    expect(waveformFinder, findsOneWidget);

    final topLeft = tester.getTopLeft(waveformFinder);

    // Initial state: no scrub delta displayed
    expect(
        find.textContaining('s', findRichText: true).evaluate().where((e) {
          final widget = e.widget;
          if (widget is Text &&
              (widget.data?.startsWith('+') == true ||
                  widget.data?.startsWith('-') == true)) {
            return true;
          }
          return false;
        }),
        isEmpty);

    // Start scrubbing forward from left (e.g. x=20 to x=150)
    final gesture = await tester.startGesture(topLeft + const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Drag forward
    await gesture.moveTo(
        topLeft + const Offset(150, 20)); // ~50% of 120s = 60s -> delta = +30s
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Delta badge should now be visible and formatted in seconds (e.g. +30s)
    final deltaFinder = find.textContaining('s').evaluate().where((e) {
      final widget = e.widget;
      if (widget is Text &&
          (widget.data?.startsWith('+') == true ||
              widget.data?.startsWith('-') == true)) {
        return true;
      }
      return false;
    });
    expect(deltaFinder, isNotEmpty);

    // End drag
    await gesture.up();
    await tester.pumpAndSettle();

    // After settling, delta badge is gone
    final settledDelta = find.textContaining('s').evaluate().where((e) {
      final widget = e.widget;
      if (widget is Text &&
          (widget.data?.startsWith('+') == true ||
              widget.data?.startsWith('-') == true)) {
        return true;
      }
      return false;
    });
    expect(settledDelta, isEmpty);
  });
}

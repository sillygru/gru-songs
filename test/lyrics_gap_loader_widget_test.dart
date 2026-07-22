import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/widgets/lyrics_gap_loader.dart';

void main() {
  Widget wrap(double progress) {
    return MaterialApp(
      home: Scaffold(
        body: LyricsGapLoader(progress: progress, accent: Colors.teal),
      ),
    );
  }

  /// The pulse controller repeats forever, so pumpAndSettle would never
  /// return — every test steps frames explicitly and tears the tree down.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('renders three dots', (tester) async {
    await tester.pumpWidget(wrap(0.1));

    final row = tester.widget<Row>(find.byType(Row));
    expect(row.children.length, 3);

    await teardown(tester);
  });

  testWidgets('survives progress changes without restarting', (tester) async {
    // The old loader reset its controller on every position tick; this is the
    // regression cover for that.
    await tester.pumpWidget(wrap(0.05));

    for (final progress in [0.2, 0.4, 0.6, 0.8, 0.95, 1.0]) {
      await tester.pumpWidget(wrap(progress));
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(LyricsGapLoader), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('fades in at the start and out at the end', (tester) async {
    await tester.pumpWidget(wrap(0));
    // TweenAnimationBuilder has no prior value to animate from on first build.
    await tester.pump();
    final entering = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    await teardown(tester);

    await tester.pumpWidget(wrap(0.5));
    await tester.pump();
    final visible = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    await teardown(tester);

    await tester.pumpWidget(wrap(1.0));
    await tester.pump();
    final leaving = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    expect(entering, lessThan(visible));
    expect(leaving, lessThan(visible));

    await teardown(tester);
  });

  testWidgets('keeps a stable row width as dots fill', (tester) async {
    await tester.pumpWidget(wrap(0.05));
    await tester.pump();
    final earlyWidth = tester.getSize(find.byType(Row)).width;

    await teardown(tester);

    await tester.pumpWidget(wrap(0.78));
    await tester.pump();
    final fullWidth = tester.getSize(find.byType(Row)).width;

    expect(fullWidth, earlyWidth);

    await teardown(tester);
  });
}

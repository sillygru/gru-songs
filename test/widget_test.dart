import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/main.dart';

void main() {
  testWidgets('App renders and shows SetupScreen by default',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: WispieApp(),
      ),
    );

    // Verify that we are on the SetupScreen
    expect(find.text('Wispie'), findsOneWidget);
    expect(find.text('Your personal music library'), findsOneWidget);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/main.dart';

void main() {
  testWidgets('App renders and shows AuthScreen by default',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: GruSongsApp(),
      ),
    );

    // Verify that we are on the AuthScreen by checking for the title
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}

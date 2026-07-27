import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/main.dart';
import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

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

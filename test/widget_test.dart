import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/main.dart';
import 'package:wispie/presentation/screens/setup_screen.dart';
import 'package:wispie/presentation/widgets/wispie_ghost_widget.dart';
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

    // Verify that we are on the SetupScreen with Wispie ghost mascot
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.byType(WispieGhostWidget), findsOneWidget);
  });
}

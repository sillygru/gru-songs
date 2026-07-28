import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/components/app_icon.dart';
import 'package:wispie/presentation/tokens/app_icons.dart';
import 'package:wispie/presentation/widgets/auto_backup_indicator.dart';
import 'package:wispie/providers/auto_backup_provider.dart';
import 'package:wispie/services/auto_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'AutoBackupIndicator shows complete message and clears on close tap',
      (tester) async {
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AutoBackupIndicator(),
          ),
        ),
      ),
    );

    expect(find.byType(AutoBackupIndicator), findsOneWidget);
    expect(find.text('Auto-Backup Complete'), findsNothing);

    // Set auto backup completed result
    container.read(autoBackupProvider.notifier).state = AutoBackupState(
      lastResult: AutoBackupResult(
        success: true,
        backupFilename: 'wispie_backup_123.zip',
      ),
    );

    await tester.pump();
    expect(find.text('Auto-Backup Complete'), findsOneWidget);
    expect(find.text('wispie_backup_123.zip'), findsOneWidget);

    // Tap close button
    final closeFinder = find.byWidgetPredicate(
      (w) => w is AppIcon && w.icon == AppIcons.close,
    );
    expect(closeFinder, findsOneWidget);
    await tester.tap(closeFinder);
    await tester.pumpAndSettle();

    expect(container.read(autoBackupProvider).lastResult, isNull);
    expect(find.text('Auto-Backup Complete'), findsNothing);
  });

  testWidgets('AutoBackupIndicator can be dismissed by swiping horizontally',
      (tester) async {
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AutoBackupIndicator(),
          ),
        ),
      ),
    );

    container.read(autoBackupProvider.notifier).state = AutoBackupState(
      lastResult: AutoBackupResult(
        success: false,
        errorMessage: 'Backup failed test',
      ),
    );

    await tester.pump();
    expect(find.text('Auto-Backup Failed'), findsOneWidget);

    // Drag to the left (dismiss)
    await tester.drag(find.text('Auto-Backup Failed'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(container.read(autoBackupProvider).lastResult, isNull);
    expect(find.text('Auto-Backup Failed'), findsNothing);
  });

  testWidgets('Permission error indicator shows Grant button and Close button',
      (tester) async {
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AutoBackupIndicator(),
          ),
        ),
      ),
    );

    container.read(autoBackupProvider.notifier).state = AutoBackupState(
      hasPermissionError: true,
    );

    await tester.pump();
    expect(find.text('Permission Required'), findsOneWidget);
    expect(find.text('Grant'), findsOneWidget);

    // Tap close button on permission error indicator
    final closeFinder = find.byWidgetPredicate(
      (w) => w is AppIcon && w.icon == AppIcons.close,
    );
    expect(closeFinder, findsOneWidget);
    await tester.tap(closeFinder);
    await tester.pumpAndSettle();

    expect(container.read(autoBackupProvider).hasPermissionError, isFalse);
    expect(find.text('Permission Required'), findsNothing);
  });
}

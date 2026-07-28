import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/providers/auto_backup_provider.dart';
import 'package:wispie/services/auto_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('AutoBackupState copyWith clearLastResult removes lastResult', () {
    final result = AutoBackupResult(success: true, backupFilename: 'test.zip');
    final state = AutoBackupState(lastResult: result);
    expect(state.lastResult, isNotNull);

    final cleared = state.copyWith(clearLastResult: true);
    expect(cleared.lastResult, isNull);
  });

  test('clearLastError resets lastResult and hasPermissionError', () async {
    final notifier = container.read(autoBackupProvider.notifier);
    final result = AutoBackupResult(
      success: false,
      errorMessage: 'Error',
      permissionDenied: true,
    );

    notifier.state = container.read(autoBackupProvider).copyWith(
          lastResult: result,
          hasPermissionError: true,
        );

    expect(container.read(autoBackupProvider).lastResult, isNotNull);
    expect(container.read(autoBackupProvider).hasPermissionError, isTrue);

    await notifier.clearLastError();

    expect(container.read(autoBackupProvider).lastResult, isNull);
    expect(container.read(autoBackupProvider).hasPermissionError, isFalse);
  });
}

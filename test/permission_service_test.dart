import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/android_storage_service.dart';
import 'package:wispie/services/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AndroidStorageService.setMockSdkInt(null);
  });

  group('AndroidStorageService.getSdkInt', () {
    test('returns mocked SDK version when set', () async {
      AndroidStorageService.setMockSdkInt(29);
      final sdk = await AndroidStorageService.getSdkInt();
      expect(sdk, 29);
    });

    test('returns 0 on non-Android platform when unmocked', () async {
      if (!Platform.isAndroid) {
        AndroidStorageService.setMockSdkInt(null);
        final sdk = await AndroidStorageService.getSdkInt();
        expect(sdk, 0);
      }
    });
  });

  group('PermissionService', () {
    test('permissionServiceProvider provides singleton instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(permissionServiceProvider);
      expect(service, equals(PermissionService.instance));
    });

    test('hasStoragePermission returns true on desktop/host platforms',
        () async {
      if (!Platform.isAndroid && !Platform.isIOS) {
        final service = PermissionService.instance;
        final hasPermission = await service.hasStoragePermission();
        expect(hasPermission, isTrue);
      }
    });

    test('isStoragePermissionPermanentlyDenied returns false on non-Android',
        () async {
      if (!Platform.isAndroid) {
        final service = PermissionService.instance;
        final permanentlyDenied =
            await service.isStoragePermissionPermanentlyDenied();
        expect(permanentlyDenied, isFalse);
      }
    });
  });
}

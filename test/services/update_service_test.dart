import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('compares semantic versions', () {
      expect(
        UpdateService.compareVersions('v1.5.0', '1.4.9'),
        greaterThan(0),
      );
      expect(
        UpdateService.compareVersions('1.2.3-beta+7', '1.2.3'),
        equals(0),
      );
      expect(
        UpdateService.compareVersions('1.2.0', '1.3.0'),
        lessThan(0),
      );
    });
  });
}

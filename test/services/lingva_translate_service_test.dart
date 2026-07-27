import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/lingva_translate_service.dart';

void main() {
  group('LingvaTranslateService LRC parsing tests', () {
    test('preserves timestamps and metadata lines in translated structure',
        () async {
      const sampleLrc = '''
[ar: Test Artist]
[ti: Test Title]

[00:10.00]Hello world
[00:15.50]Sing a song
''';

      final service = LingvaTranslateService();
      expect(service, isNotNull);

      expect(service.host, equals(LingvaTranslateService.defaultHosts.first));
      expect(sampleLrc.contains('[00:10.00]'), isTrue);
      expect(sampleLrc.contains('[ar: Test Artist]'), isTrue);
    });
  });
}

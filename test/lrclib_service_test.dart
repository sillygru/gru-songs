import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/lrclib_service.dart';

void main() {
  group('LrclibService.cleanTag', () {
    test('returns null for null, empty and whitespace-only tags', () {
      expect(LrclibService.cleanTag(null), isNull);
      expect(LrclibService.cleanTag(''), isNull);
      expect(LrclibService.cleanTag('   '), isNull);
    });

    test('drops the scanner placeholders regardless of case', () {
      expect(LrclibService.cleanTag('Unknown Title'), isNull);
      expect(LrclibService.cleanTag('Unknown Artist'), isNull);
      expect(LrclibService.cleanTag('Unknown Album'), isNull);
      expect(LrclibService.cleanTag('unknown artist'), isNull);
      expect(LrclibService.cleanTag('UNKNOWN ARTIST'), isNull);
      expect(LrclibService.cleanTag('  Unknown Artist  '), isNull);
    });

    test('keeps and trims a real tag', () {
      expect(LrclibService.cleanTag(' Yoza '), 'Yoza');
      expect(LrclibService.cleanTag('Pretty Lies'), 'Pretty Lies');
      // A real tag that merely contains the word "unknown" is untouched.
      expect(LrclibService.cleanTag('Unknown Mortal Orchestra'),
          'Unknown Mortal Orchestra');
    });
  });
}

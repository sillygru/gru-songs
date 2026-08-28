import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/lingva_translate_service.dart';

void main() {
  group('LingvaTranslateService.hasSignificantForeignScript', () {
    test('plain English lines are not foreign', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('I walk alone'),
        isFalse,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('Come on, yeah!'),
        isFalse,
      );
    });

    test('accented Latin script still counts as Latin', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('Café déjà vu'),
        isFalse,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('señorita'),
        isFalse,
      );
    });

    test('numbers, punctuation and emoji never flag a line', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('3, 2, 1 — go!'),
        isFalse,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript(
            'Party time \u{1F3B5}'),
        isFalse,
      );
      // Full-width punctuation is punctuation, not a foreign script marker.
      expect(
        LingvaTranslateService.hasSignificantForeignScript('さよなら、またね'),
        isTrue,
      );
    });

    test('non-Latin scripts are foreign', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('こんにちは世界'),
        isTrue,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('안녕하세요'),
        isTrue,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('Привет мир'),
        isTrue,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('สวัสดี'),
        isTrue,
      );
    });

    test('a mostly-English line dipping into kana is still foreign', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('I love you 大好き'),
        isTrue,
      );
      expect(
        LingvaTranslateService.hasSignificantForeignScript('Yeah yeah 泣きたい'),
        isTrue,
      );
    });

    test('a stray pair of characters is below the threshold', () {
      expect(
        LingvaTranslateService.hasSignificantForeignScript('はい'),
        isFalse,
      );
    });
  });

  group('LingvaTranslateService.lineNeedsTranslation', () {
    test('Latin-script targets: only foreign-script lines need translation',
        () {
      expect(
        LingvaTranslateService.lineNeedsTranslation('I walk alone', 'en'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('こんにちは世界', 'en'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('La vie en rose', 'en'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('안녕하세요', 'es'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('I walk alone', 'es'),
        isFalse,
      );
    });

    test('non-Latin targets: lines already in that script stay put', () {
      expect(
        LingvaTranslateService.lineNeedsTranslation('サヨナラ', 'ja'),
        isFalse,
      );
      // Short but wholly kana lines are still Japanese.
      expect(
        LingvaTranslateService.lineNeedsTranslation('たのし', 'ja'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('Goodbye', 'ja'),
        isTrue,
      );
      // A line that only dips into kana is mostly not Japanese yet.
      expect(
        LingvaTranslateService.lineNeedsTranslation('Goodbye さよなら', 'ja'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('안녕하세요', 'ko'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('Привет мир', 'ru'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('Hello world', 'ru'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('สวัสดี', 'th'),
        isFalse,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('Hello', 'th'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('世界你好', 'zh'),
        isFalse,
      );
    });

    test(
        'a foreign-script line still needs translation for a different '
        'non-Latin target', () {
      expect(
        LingvaTranslateService.lineNeedsTranslation('Привет мир', 'zh'),
        isTrue,
      );
      expect(
        LingvaTranslateService.lineNeedsTranslation('こんにちは世界', 'ko'),
        isTrue,
      );
    });
  });

  group('LingvaTranslateService.spliceTranslations', () {
    test('kept lines keep their original text in place', () {
      expect(
        LingvaTranslateService.spliceTranslations(
          originalLines: const [
            '[00:01.00]I walk alone',
            '[00:04.00]こんにちは世界',
            '[00:08.00]The road is long',
          ],
          needsTranslation: const [false, true, false],
          translatedLines: const ['[00:04.00]Hello world'],
        ),
        equals(const [
          '[00:01.00]I walk alone',
          '[00:04.00]Hello world',
          '[00:08.00]The road is long',
        ]),
      );
    });

    test('null needsTranslation replaces every line', () {
      expect(
        LingvaTranslateService.spliceTranslations(
          originalLines: const ['A', 'B'],
          needsTranslation: null,
          translatedLines: const ['X', 'Y'],
        ),
        equals(const ['X', 'Y']),
      );
    });
  });

  group('LyricLine.alignTranslation', () {
    test('matches translated lines by timestamp instead of shifted indexes',
        () {
      final source = LyricLine.parse(
        '[00:01.00]First\n[00:02.00]Second\n[00:03.00]Third',
      );
      final translated =
          LyricLine.parse('[00:02.00]Segundo\n[00:03.00]Tercero');

      final aligned = LyricLine.alignTranslation(source, translated);

      expect(aligned, hasLength(3));
      expect(aligned[0], isNull);
      expect(aligned[1]?.text, 'Segundo');
      expect(aligned[2]?.text, 'Tercero');
    });
  });

  group('LingvaTranslateService.lyricsNeedTranslation', () {
    test('English lyrics targeting English do not need translation', () {
      expect(
        LingvaTranslateService.lyricsNeedTranslation(
          '[00:01.00]I walk a lonely road\n[00:04.00]The only one that I have ever known',
          'en',
        ),
        isFalse,
      );
    });

    test('Japanese lyrics targeting English need translation', () {
      expect(
        LingvaTranslateService.lyricsNeedTranslation(
          '[00:01.00]こんにちは世界\n[00:04.00]さようなら',
          'en',
        ),
        isTrue,
      );
    });

    test('English lyrics targeting Japanese need translation', () {
      expect(
        LingvaTranslateService.lyricsNeedTranslation(
          '[00:01.00]Hello world\n[00:04.00]Goodbye',
          'ja',
        ),
        isTrue,
      );
    });

    test('Japanese lyrics targeting Japanese do not need translation', () {
      expect(
        LingvaTranslateService.lyricsNeedTranslation(
          '[00:01.00]こんにちは世界\n[00:04.00]さようなら',
          'ja',
        ),
        isFalse,
      );
    });
  });

  group('LingvaTranslateService.translateLyrics', () {
    test('all lines already in the target script skip without translating',
        () async {
      // Japanese lyrics targeting Japanese must resolve offline — the early
      // return happens before any backend is contacted.
      final response = await LingvaTranslateService().translateLyrics(
        lyrics: 'こんにちは世界\nさようなら',
        targetLang: 'ja',
      );
      expect(response.text, 'こんにちは世界\nさようなら');
      expect(response.detectedSourceLang, 'ja');
    });
  });
}

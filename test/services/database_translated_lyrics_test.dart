import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/database_service.dart';
import '../test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
    await DatabaseService.instance.init();
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    testEnv.tearDown();
  });

  group('DatabaseService Translated Lyrics', () {
    const filename = 'test_song.mp3';
    const targetLang = 'es';
    const content = '[00:10.00] Hola mundo';

    test(
        'saves and retrieves translated lyrics by filename and target language',
        () async {
      await DatabaseService.instance
          .saveTranslatedLyrics(filename, targetLang, content);

      final retrieved = await DatabaseService.instance
          .getTranslatedLyrics(filename, targetLang);
      expect(retrieved, equals(content));
    });

    test('returns null for nonexistent translation', () async {
      final retrieved =
          await DatabaseService.instance.getTranslatedLyrics(filename, 'fr');
      expect(retrieved, isNull);
    });

    test('does not reuse a translation for changed source lyrics', () async {
      const oldSource = '[00:10.00] Hello';
      const newSource = '[00:10.00] Goodbye';
      await DatabaseService.instance.saveTranslatedLyrics(
        filename,
        'de',
        '[00:10.00] Hallo',
        sourceContent: oldSource,
      );

      expect(
        await DatabaseService.instance.getTranslatedLyrics(
          filename,
          'de',
          sourceContent: oldSource,
        ),
        '[00:10.00] Hallo',
      );
      expect(
        await DatabaseService.instance.getTranslatedLyrics(
          filename,
          'de',
          sourceContent: newSource,
        ),
        isNull,
      );
    });

    test('deletes translated lyrics by target language or filename', () async {
      await DatabaseService.instance
          .saveTranslatedLyrics(filename, 'fr', '[00:10.00] Bonjour');

      await DatabaseService.instance.deleteTranslatedLyrics(filename, 'fr');
      expect(await DatabaseService.instance.getTranslatedLyrics(filename, 'fr'),
          isNull);
      expect(
          await DatabaseService.instance
              .getTranslatedLyrics(filename, targetLang),
          equals(content));

      await DatabaseService.instance.deleteTranslatedLyrics(filename);
      expect(
          await DatabaseService.instance
              .getTranslatedLyrics(filename, targetLang),
          isNull);
    });
  });
}

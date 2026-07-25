import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/settings_entry.dart';
import 'package:wispie/domain/services/settings_search_service.dart';
import 'package:wispie/presentation/screens/settings_registry.dart';

void main() {
  const service = SettingsSearchService();

  List<SettingsEntry> find(String query) =>
      service.search(settingsRegistry, query);

  group('SettingsSearchService', () {
    test('empty and whitespace-only queries return nothing', () {
      expect(service.search(settingsRegistry, ''), isEmpty);
      expect(service.search(settingsRegistry, '   '), isEmpty);
    });

    test('matches a title prefix', () {
      expect(
        find('fade').map((e) => e.anchorId),
        containsAll([
          'playback.fade_out',
          'playback.fade_in',
          'playback.fade_play',
        ]),
      );
    });

    test('matches on a keyword the title never mentions', () {
      final ids = find('gapless').map((e) => e.anchorId);
      expect(ids, containsAll(['playback.fade_out', 'playback.fade_in']));
    });

    test('every token must match — more words narrow the result', () {
      final fade = find('fade');
      final fadePause = find('fade pause');

      expect(fadePause.length, lessThan(fade.length));
      expect(fadePause.first.anchorId, 'playback.fade_pause');
    });

    test('title hits outrank subtitle and keyword hits', () {
      final results = find('backup');

      // "Auto Backup" starts with the token; the entries that merely mention
      // backups in a subtitle or keyword come after it.
      expect(results.first.title, startsWith('Backup'));
      expect(
        results.map((e) => e.anchorId),
        containsAll(['misc.auto_backup', 'data.export']),
      );
      expect(
        results.indexWhere((e) => e.anchorId == 'misc.auto_backup'),
        lessThan(results.indexWhere((e) => e.anchorId == 'data.export')),
      );
    });

    test('matches words inside a title, not arbitrary substrings', () {
      expect(find('videos').map((e) => e.anchorId),
          contains('library.include_videos'));
      expect(find('ideos'), isEmpty);
    });

    test('search is case-insensitive', () {
      expect(
        find('TELEMETRY').single.anchorId,
        'misc.telemetry',
      );
    });

    test('results are capped', () {
      expect(
        find('a').length,
        lessThanOrEqualTo(SettingsSearchService.maxResults),
      );
    });
  });

  group('settings registry', () {
    test('keys are unique', () {
      final keys = settingsRegistry.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every entry has a title and a breadcrumb', () {
      for (final entry in settingsRegistry) {
        expect(entry.title, isNotEmpty, reason: entry.key);
        expect(entry.breadcrumb, isNotEmpty, reason: entry.key);
      }
    });

    // The registry and the rows it points at are separate edits, so a renamed
    // or deleted row would otherwise leave a result that jumps to a page and
    // highlights nothing.
    test('every anchorId is wired to a row via searchId', () {
      final sources = Directory('lib/presentation/screens')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('settings_registry.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      for (final entry in settingsRegistry) {
        final anchorId = entry.anchorId;
        if (anchorId == null) continue;

        expect(
          sources.contains("searchId: '$anchorId'") ||
              sources.contains("id: '$anchorId'"),
          isTrue,
          reason: 'No row carries searchId "$anchorId"',
        );
      }
    });
  });
}

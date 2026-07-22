import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/services/backup_manifest.dart';
import 'package:wispie/services/backup_service.dart';
import 'package:wispie/services/import_options.dart';

import 'test_helpers.dart';

/// Round-trip coverage for the content types that used to be silently dropped:
/// settings selected on their own, and every cache bucket.
void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  setUp(() async {
    // Each test starts from a clean prefs store and no leftover archives.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final backupsDir = Directory(p.join(testEnv.tempPath, 'backups'));
    if (await backupsDir.exists()) {
      await backupsDir.delete(recursive: true);
    }
  });

  BackupInfo backupInfoFor(String filename) {
    final file = File(p.join(testEnv.tempPath, 'backups', filename));
    return BackupInfo(
      number: 1,
      timestamp: DateTime.now(),
      filename: filename,
      file: file,
      sizeBytes: file.lengthSync(),
    );
  }

  Future<void> seedCacheSources() async {
    final root = testEnv.tempPath;
    Future<void> write(String relative, String content) async {
      final file = File(p.join(root, relative));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    await write(p.join('extracted_covers', 'song.jpg'), 'cover-bytes');
    await write(
        p.join('gru_cache_v3', 'blurred_cache', 'blurred_abc.jpg'), 'blurred');
    await write(
        p.join('gru_cache_v3', 'notification_cover_cache', 'abc.jpg'), 'notif');
    await write('cached_songs.json', '[{"filename":"a.mp3"}]');
    await write('wispie_search_index.db', 'index-bytes');
    await write(p.join('gru_cache_v3', 'waveform_abc.json'), '[1,2,3]');
    await write('palette_cache.json', '{"abc":"#ffffff"}');
    await write(p.join('palettes', 'abc.json'), '{"swatches":[]}');
    await write(p.join('gru_cache_v3', 'lyrics_cache', 'abc.json'), 'lyrics');
  }

  Future<void> deleteCacheSources() async {
    final root = testEnv.tempPath;
    for (final relative in [
      'extracted_covers',
      'palettes',
      'gru_cache_v3',
    ]) {
      final dir = Directory(p.join(root, relative));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    for (final relative in [
      'cached_songs.json',
      'wispie_search_index.db',
      'palette_cache.json',
    ]) {
      final file = File(p.join(root, relative));
      if (await file.exists()) await file.delete();
    }
  }

  const cacheTypes = {
    BackupContentType.coverCache,
    BackupContentType.libraryCache,
    BackupContentType.searchIndex,
    BackupContentType.waveformCache,
    BackupContentType.colorCache,
    BackupContentType.lyricsCache,
  };

  const cacheCategories = {
    ImportDataCategory.coverCache,
    ImportDataCategory.libraryCache,
    ImportDataCategory.searchIndex,
    ImportDataCategory.waveformCache,
    ImportDataCategory.colorCache,
    ImportDataCategory.lyricsCache,
  };

  group('settings-only backup', () {
    test('archive contains app_settings.json without user data or stats',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', 'dark');
      await prefs.setBool('show_waveform', true);

      final filename = await BackupService.instance.createBackup(
        BackupOptions(contentTypes: {BackupContentType.userSettings}),
      );

      final validation = await BackupService.instance
          .validateBackupFile(backupInfoFor(filename).file);

      expect(validation['hasAppSettingsJson'], isTrue);
      expect(
        File(p.join(validation['importPath'] as String, 'app_settings.json'))
            .existsSync(),
        isTrue,
      );
      await BackupService.instance.discardValidation(validation);
    });

    test('restore applies the settings back', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', 'dark');
      await prefs.setInt('minimum_track_duration_ms', 42000);
      await prefs.setBool('telemetry_enabled', false);

      final filename = await BackupService.instance.createBackup(
        BackupOptions(contentTypes: {BackupContentType.userSettings}),
      );

      await prefs.setString('theme_mode', 'light');
      await prefs.setInt('minimum_track_duration_ms', 1);
      await prefs.setBool('telemetry_enabled', true);

      await BackupService.instance.restoreFromBackup(
        backupInfoFor(filename),
        options: const ImportOptions(
          categories: {
            ImportDataCategory.themeSettings,
            ImportDataCategory.scannerSettings,
            ImportDataCategory.uiSettings,
          },
          restoreDatabases: false,
        ),
      );

      final restored = await SharedPreferences.getInstance();
      await restored.reload();
      expect(restored.getString('theme_mode'), 'dark');
      expect(restored.getInt('minimum_track_duration_ms'), 42000);
      // telemetry_enabled belongs to the UI category and must survive too.
      expect(restored.getBool('telemetry_enabled'), isFalse);
    });
  });

  group('cache backup', () {
    test('every bucket round-trips to its live location', () async {
      await seedCacheSources();

      final filename = await BackupService.instance.createBackup(
        BackupOptions(contentTypes: cacheTypes),
      );

      await deleteCacheSources();

      await BackupService.instance.restoreFromBackup(
        backupInfoFor(filename),
        options: const ImportOptions(
          categories: cacheCategories,
          restoreDatabases: false,
        ),
      );

      final root = testEnv.tempPath;
      expect(
          File(p.join(root, 'extracted_covers', 'song.jpg')).readAsStringSync(),
          'cover-bytes');
      expect(
          File(p.join(root, 'gru_cache_v3', 'blurred_cache', 'blurred_abc.jpg'))
              .existsSync(),
          isTrue);
      expect(
          File(p.join(
                  root, 'gru_cache_v3', 'notification_cover_cache', 'abc.jpg'))
              .existsSync(),
          isTrue);
      expect(File(p.join(root, 'cached_songs.json')).existsSync(), isTrue);
      expect(File(p.join(root, 'wispie_search_index.db')).existsSync(), isTrue);
      expect(
          File(p.join(root, 'gru_cache_v3', 'waveform_abc.json'))
              .readAsStringSync(),
          '[1,2,3]');
      expect(File(p.join(root, 'palette_cache.json')).existsSync(), isTrue);
      expect(File(p.join(root, 'palettes', 'abc.json')).existsSync(), isTrue);
      expect(
          File(p.join(root, 'gru_cache_v3', 'lyrics_cache', 'abc.json'))
              .readAsStringSync(),
          'lyrics');

      await deleteCacheSources();
    });

    test('waveform bucket does not swallow unrelated v3 files', () async {
      await seedCacheSources();
      final stray =
          File(p.join(testEnv.tempPath, 'gru_cache_v3', 'other.json'));
      await stray.writeAsString('unrelated');

      final filename = await BackupService.instance.createBackup(
        BackupOptions(contentTypes: {BackupContentType.waveformCache}),
      );

      final validation = await BackupService.instance
          .validateBackupFile(backupInfoFor(filename).file);
      final waveformDir = Directory(
          p.join(validation['importPath'] as String, 'cache', 'waveforms'));

      final staged = waveformDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList();
      expect(staged, ['waveform_abc.json']);

      await BackupService.instance.discardValidation(validation);
      await deleteCacheSources();
    });

    test('cache-only archive validates and offers exactly the cache categories',
        () async {
      await seedCacheSources();

      final filename = await BackupService.instance.createBackup(
        BackupOptions(contentTypes: cacheTypes),
      );

      final validation = await BackupService.instance
          .validateBackupFile(backupInfoFor(filename).file);

      expect(validation['valid'], isTrue);
      expect(validation['hasStatsDb'], isFalse);
      expect(validation['hasDataDb'], isFalse);
      expect(BackupService.instance.getAvailableCategories(validation),
          cacheCategories);

      await BackupService.instance.discardValidation(validation);
      await deleteCacheSources();
    });
  });

  test('restore without databases still applies settings and cache', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', 'dark');
    await seedCacheSources();

    final filename = await BackupService.instance.createBackup(
      BackupOptions(contentTypes: {
        BackupContentType.userSettings,
        ...cacheTypes,
      }),
    );

    await prefs.setString('theme_mode', 'light');
    await deleteCacheSources();

    await BackupService.instance.restoreFromBackup(
      backupInfoFor(filename),
      options: const ImportOptions(
        categories: {
          ImportDataCategory.themeSettings,
          ...cacheCategories,
        },
        // No databases in the archive: this used to abort the whole restore.
        restoreDatabases: true,
      ),
    );

    final restored = await SharedPreferences.getInstance();
    await restored.reload();
    expect(restored.getString('theme_mode'), 'dark');
    expect(
        File(p.join(testEnv.tempPath, 'extracted_covers', 'song.jpg'))
            .existsSync(),
        isTrue);

    await deleteCacheSources();
  });

  test('backup content types persist for automatic backups', () async {
    final options = await BackupService.instance.defaultBackupOptions();
    expect(options.contentTypes, {
      BackupContentType.userStats,
      BackupContentType.userData,
      BackupContentType.userSettings,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('auto_backup_content_types', [
      BackupContentType.userSettings.name,
      BackupContentType.lyricsCache.name
    ]);

    final updated = await BackupService.instance.defaultBackupOptions();
    expect(updated.contentTypes,
        {BackupContentType.userSettings, BackupContentType.lyricsCache});
  });

  test('archive entries that escape the extraction root are ignored', () {
    final root = Directory.systemTemp.createTempSync('zip_slip_').path;
    expect(safeArchiveTarget(root, '../evil.txt'), isNull);
    expect(safeArchiveTarget(root, 'data/../../evil.txt'), isNull);
    expect(safeArchiveTarget(root, 'data/songs.json'), isNotNull);
  });

  test('settings export omits identity keys', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', 'someone');
    await prefs.setString('theme_mode', 'dark');

    final filename = await BackupService.instance.createBackup(
      BackupOptions(contentTypes: {BackupContentType.userSettings}),
    );

    final validation = await BackupService.instance
        .validateBackupFile(backupInfoFor(filename).file);
    final settings = jsonDecode(
      File(p.join(validation['importPath'] as String, 'app_settings.json'))
          .readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(settings.containsKey('theme_mode'), isTrue);
    expect(settings.containsKey('username'), isFalse);

    await BackupService.instance.discardValidation(validation);
  });
}

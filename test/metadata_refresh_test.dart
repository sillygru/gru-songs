import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/providers/providers.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/file_manager_service.dart';

import 'test_helpers.dart';

const _appVersion = '3.26.5-beta+310';

class _MockPackageInfoPlatform extends PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    return PackageInfoData(
      appName: 'wispie',
      packageName: 'com.example.wispie',
      version: '3.26.5-beta',
      buildNumber: '310',
      buildSignature: '',
    );
  }
}

/// Stands in for the real tag writer so these tests exercise the provider's
/// cache-refresh path without invoking FFmpeg or touching an audio file.
class _FakeFileManager extends FileManagerService {
  final List<String> lyricsWrites = [];
  final List<List<String>> metadataWrites = [];

  @override
  Future<void> updateLyrics(Song song, String lyricsContent) async {
    lyricsWrites.add(lyricsContent);
  }

  @override
  Future<void> updateSongMetadata(
      Song song, String title, String artist, String album) async {
    metadataWrites.add([title, artist, album]);
  }
}

/// Saving metadata used to flip `songsProvider` to `AsyncLoading` and re-scan
/// the whole library for a one-file change, which is what made the app freeze
/// on every save. These tests pin the targeted behaviour that replaced it.
void main() {
  late TestEnvironment testEnv;

  const song = Song(
    title: 'One',
    artist: 'Artist',
    album: 'Album',
    filename: 'one.mp3',
    url: '/music/one.mp3',
    hasLyrics: false,
    duration: Duration(seconds: 100),
  );

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
    PackageInfoPlatform.instance = _MockPackageInfoPlatform();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    // Keep the startup scan out of the way — it is exactly what these tests
    // assert does not run.
    await prefs.setString('last_scan_version', _appVersion);
    await prefs.setBool('startup_cache_maintenance_pending', false);

    final db = DatabaseService.forTest();
    DatabaseService.instance = db;
    await db.init();
    await db.clearSongs();
    await db.insertSongsBatch([song]);
  });

  Future<(ProviderContainer, _FakeFileManager, List<bool>)> boot() async {
    final fileManager = _FakeFileManager();
    final container = ProviderContainer(overrides: [
      fileManagerServiceProvider.overrideWithValue(fileManager),
    ]);
    addTearDown(container.dispose);

    await container.read(songsProvider.future);

    final sawLoading = <bool>[];
    container.listen(
      songsProvider,
      (_, next) => sawLoading.add(next.isLoading),
      fireImmediately: false,
    );

    return (container, fileManager, sawLoading);
  }

  test('updateLyrics writes the file and publishes without a loading state',
      () async {
    final (container, fileManager, sawLoading) = await boot();

    await container
        .read(songsProvider.notifier)
        .updateLyrics(song, '[00:01.00] hello');

    expect(fileManager.lyricsWrites, ['[00:01.00] hello']);
    expect(sawLoading, everyElement(isFalse),
        reason: 'a one-file edit must not blank out every screen '
            'watching songsProvider');

    final updated = (container.read(songsProvider).value ?? const <Song>[])
        .firstWhere((s) => s.filename == 'one.mp3');
    expect(updated.hasLyrics, isTrue);
  });

  test('updateLyrics persists has_lyrics without a rescan', () async {
    final (container, _, _) = await boot();

    await container.read(songsProvider.notifier).updateLyrics(song, 'words');

    final stored = await DatabaseService.instance.getAllSongs();
    expect(stored, hasLength(1));
    expect(stored.single.hasLyrics, isTrue);
  });

  test('clearing lyrics clears the flag', () async {
    final (container, _, _) = await boot();

    await container.read(songsProvider.notifier).updateLyrics(song, '   ');

    final stored = await DatabaseService.instance.getAllSongs();
    expect(stored.single.hasLyrics, isFalse);
  });

  test('updateLyrics bumps the revision so open lyrics views reload', () async {
    final (container, _, _) = await boot();

    final before = container.read(lyricsRevisionProvider);
    await container.read(songsProvider.notifier).updateLyrics(song, 'words');

    expect(container.read(lyricsRevisionProvider), greaterThan(before));
  });

  test('updateSongMetadata publishes the new tags to state and the DB',
      () async {
    final (container, fileManager, sawLoading) = await boot();

    await container
        .read(songsProvider.notifier)
        .updateSongMetadata(song, 'New Title', 'New Artist', 'New Album');

    expect(fileManager.metadataWrites, [
      ['New Title', 'New Artist', 'New Album']
    ]);
    expect(sawLoading, everyElement(isFalse));

    final updated = (container.read(songsProvider).value ?? const <Song>[])
        .firstWhere((s) => s.filename == 'one.mp3');
    expect(updated.title, 'New Title');
    expect(updated.artist, 'New Artist');
    expect(updated.album, 'New Album');
    // Untouched fields must survive the edit.
    expect(updated.duration, song.duration);

    final stored = await DatabaseService.instance.getAllSongs();
    expect(stored.single.title, 'New Title');
  });
}

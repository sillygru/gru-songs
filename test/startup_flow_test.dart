import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/providers/providers.dart';
import 'package:gru_songs/services/database_service.dart';
import 'package:gru_songs/services/scanner_service.dart';
import 'package:gru_songs/services/storage_service.dart';

import 'test_helpers.dart';

class _FakeStorageService extends StorageService {
  final List<Map<String, String>> folders;

  _FakeStorageService(this.folders);

  @override
  Future<List<Map<String, String>>> getMusicFolders(
      {bool forceRefresh = false}) async {
    return folders;
  }
}

class _FakeScannerService extends ScannerService {
  int calls = 0;

  @override
  Future<List<Song>> scanDirectory(
    String path, {
    List<Song>? existingSongs,
    String? lyricsPath,
    Map<String, int>? playCounts,
    void Function(double progress)? onProgress,
    void Function(List<Song>)? onComplete,
    bool includeVideos = true,
    int minimumFileSizeBytes = 0,
  }) async {
    calls += 1;
    return [];
  }
}

void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  test('returns cached songs immediately when the DB already has songs',
      () async {
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearSongs();
    await DatabaseService.instance.insertSongsBatch([
      const Song(
        title: 'Cached',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/cached.mp3',
        url: '/music/cached.mp3',
      ),
    ]);

    final fakeScanner = _FakeScannerService();
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(_FakeStorageService(const [])),
        scannerServiceProvider.overrideWithValue(fakeScanner),
      ],
    );

    final songs = await container.read(songsProvider.future);
    expect(songs, hasLength(1));
    expect(songs.single.filename, '/music/cached.mp3');
    expect(fakeScanner.calls, 0);

    container.dispose();
  });

  test('does not scan when there is no folder access to resolve', () async {
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearSongs();

    final fakeScanner = _FakeScannerService();
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(_FakeStorageService(const [])),
        scannerServiceProvider.overrideWithValue(fakeScanner),
      ],
    );

    final songs = await container.read(songsProvider.future);
    expect(songs, isEmpty);
    expect(fakeScanner.calls, 0);

    container.dispose();
  });
}

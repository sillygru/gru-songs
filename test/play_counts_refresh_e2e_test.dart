import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/providers/providers.dart';
import 'package:wispie/services/database_service.dart';

import 'test_helpers.dart';

const _appVersion = '3.23.4-beta+284';

class _MockPackageInfoPlatform extends PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    return PackageInfoData(
      appName: 'wispie',
      packageName: 'com.example.wispie',
      version: '3.23.4-beta',
      buildNumber: '284',
      buildSignature: '',
    );
  }
}

void main() {
  late TestEnvironment testEnv;

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
    await prefs.setString('last_scan_version', _appVersion);
    await prefs.setBool('startup_cache_maintenance_pending', false);
  });

  test('refreshPlayCounts updates DB, songsProvider, and playCountsProvider',
      () async {
    final db = DatabaseService.forTest();
    DatabaseService.instance = db;
    await db.init();
    await db.clearSongs();

    await db.insertSongsBatch([
      const Song(
        title: 'One',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/one.mp3',
        url: '/music/one.mp3',
      ),
    ]);

    await db.insertPlayEvent({
      'session_id': 'session-1',
      'song_filename': '/music/one.mp3',
      'timestamp': 1.0,
      'duration_played': 120.0,
      'total_length': 120.0,
      'play_ratio': 1.0,
      'foreground_duration': 120.0,
      'background_duration': 0.0,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final songs = await container.read(songsProvider.future);
    expect(songs, hasLength(1));
    expect(container.read(playCountsProvider)['/music/one.mp3'], 0);

    await container.read(songsProvider.notifier).refreshPlayCounts();

    expect(container.read(playCountsProvider)['/music/one.mp3'], 1);

    final updatedSong = (container.read(songsProvider).value ?? const <Song>[])
        .firstWhere((song) => song.filename == '/music/one.mp3');
    expect(updatedSong.playCount, 1);
    expect((await db.getPlayCounts())['/music/one.mp3'], 1);
  });
}

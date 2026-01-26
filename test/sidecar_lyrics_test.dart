import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/scanner_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getTemporaryPath() async => tempPath;
  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
  @override
  Future<String?> getLibraryPath() async => tempPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;
  @override
  Future<String?> getExternalStoragePath() async => tempPath;
  @override
  Future<List<String>?> getExternalCachePaths() async => [tempPath];
  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [tempPath];
  @override
  Future<String?> getDownloadsPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sidecar Lyrics Tests', () {
    late ScannerService scannerService;
    late Directory tempDir;

    setUp(() async {
      scannerService = ScannerService();
      tempDir = await Directory.systemTemp.createTemp('sidecar_test');
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('scanDirectory finds sidecar .lrc in same folder', () async {
      final musicDir = await Directory(p.join(tempDir.path, 'Music')).create();
      final songFile = File(p.join(musicDir.path, 'TestSong.mp3'));
      await songFile.writeAsString('dummy mp3 content');

      final lrcFile = File(p.join(musicDir.path, 'TestSong.lrc'));
      await lrcFile.writeAsString('[00:00.00]Test lyrics');

      final songs =
          await scannerService.scanDirectory(musicDir.path, playCounts: {});

      expect(songs.length, 1);
      expect(songs[0].lyricsUrl, lrcFile.path);
    });

    test('sidecar in same folder takes priority over global lyrics folder',
        () async {
      final musicDir = await Directory(p.join(tempDir.path, 'Music')).create();
      final songFile = File(p.join(musicDir.path, 'Shared.mp3'));
      await songFile.writeAsString('dummy mp3 content');

      // Local sidecar
      final localLrc = File(p.join(musicDir.path, 'Shared.lrc'));
      await localLrc.writeAsString('local lyrics');

      // Global lyrics folder
      final globalLyricsDir =
          await Directory(p.join(tempDir.path, 'GlobalLyrics')).create();
      final globalLrc = File(p.join(globalLyricsDir.path, 'Shared.lrc'));
      await globalLrc.writeAsString('global lyrics');

      final songs = await scannerService.scanDirectory(musicDir.path,
          lyricsPath: globalLyricsDir.path, playCounts: {});

      expect(songs.length, 1);
      expect(songs[0].lyricsUrl, localLrc.path);
    });

    test('falls back to global lyrics folder if sidecar not present', () async {
      final musicDir = await Directory(p.join(tempDir.path, 'Music')).create();
      final songFile = File(p.join(musicDir.path, 'Fallback.mp3'));
      await songFile.writeAsString('dummy mp3 content');

      // Global lyrics folder
      final globalLyricsDir =
          await Directory(p.join(tempDir.path, 'GlobalLyrics')).create();
      final globalLrc = File(p.join(globalLyricsDir.path, 'Fallback.lrc'));
      await globalLrc.writeAsString('global lyrics');

      final songs = await scannerService.scanDirectory(musicDir.path,
          lyricsPath: globalLyricsDir.path, playCounts: {});

      expect(songs.length, 1);
      expect(songs[0].lyricsUrl, globalLrc.path);
    });
  });
}

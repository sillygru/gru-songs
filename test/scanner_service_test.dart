import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/scanner_service.dart';
import 'dart:io';
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

  group('ScannerService Tests', () {
    late ScannerService scannerService;
    late Directory tempDir;

    setUp(() async {
      scannerService = ScannerService();
      tempDir = await Directory.systemTemp.createTemp('scanner_test');
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('scanDirectory finds supported audio files', () async {
      // Create some dummy files
      final mp3File = File(p.join(tempDir.path, 'song1.mp3'));
      await mp3File.writeAsString('dummy mp3');

      final wavFile = File(p.join(tempDir.path, 'song2.wav'));
      await wavFile.writeAsString('dummy wav');

      final txtFile = File(p.join(tempDir.path, 'not_a_song.txt'));
      await txtFile.writeAsString('dummy text');

      final songs =
          await scannerService.scanDirectory(tempDir.path, playCounts: {});

      expect(songs.length, 2);
      expect(songs.any((s) => s.filename == 'song1.mp3'), true);
      expect(songs.any((s) => s.filename == 'song2.wav'), true);
      expect(songs.any((s) => s.filename == 'not_a_song.txt'), false);
    });

    test('scanDirectory finds cover art', () async {
      final mp3File = File(p.join(tempDir.path, 'song1.mp3'));
      await mp3File.writeAsString('dummy mp3');

      final coverFile = File(p.join(tempDir.path, 'cover.jpg'));
      await coverFile.writeAsString('dummy cover');

      final songs =
          await scannerService.scanDirectory(tempDir.path, playCounts: {});

      expect(songs.length, 1);
      expect(songs[0].coverUrl, coverFile.path);
    });

    test('scanDirectory recursive search', () async {
      final subDir = await Directory(p.join(tempDir.path, 'subdir')).create();
      final mp3File = File(p.join(subDir.path, 'subsong.mp3'));
      await mp3File.writeAsString('dummy mp3');

      final songs =
          await scannerService.scanDirectory(tempDir.path, playCounts: {});

      expect(songs.length, 1);
      expect(songs[0].filename, 'subsong.mp3');
      expect(songs[0].url, mp3File.path);
    });

    test('manual extraction finds large JPEG signature', () async {
      final mp3File = File(p.join(tempDir.path, 'large_cover.mp3'));

      // Create a "file" with a JPEG signature at 300KB, ending at 800KB (500KB total)
      // This would have failed with the old 256KB limit
      final List<int> data = List.filled(1024 * 1024, 0);
      final sigPos = 300 * 1024;
      data[sigPos] = 0xFF;
      data[sigPos + 1] = 0xD8;
      data[sigPos + 2] = 0xFF;

      final endPos = 800 * 1024;
      data[endPos] = 0xFF;
      data[endPos + 1] = 0xD9;

      await mp3File.writeAsBytes(data);

      final songs =
          await scannerService.scanDirectory(tempDir.path, playCounts: {});
      expect(songs.length, 1);
      expect(songs[0].coverUrl, isNotNull);
      expect(File(songs[0].coverUrl!).existsSync(), true);

      final coverLength = await File(songs[0].coverUrl!).length();
      expect(coverLength, 500 * 1024 + 2);
    });

    test('manual extraction finds JPEG signature at the end', () async {
      final mp3File = File(p.join(tempDir.path, 'end_cover.mp3'));

      final length = 2 * 1024 * 1024; // 2MB file
      final List<int> data = List.filled(length, 0);

      // JPEG signature at length - 500KB
      final sigPos = length - 500 * 1024;
      data[sigPos] = 0xFF;
      data[sigPos + 1] = 0xD8;
      data[sigPos + 2] = 0xFF;

      final endPos = length - 100 * 1024;
      data[endPos] = 0xFF;
      data[endPos + 1] = 0xD9;

      await mp3File.writeAsBytes(data);

      final songs =
          await scannerService.scanDirectory(tempDir.path, playCounts: {});
      expect(songs.length, 1);
      expect(songs[0].coverUrl, isNotNull);

      final coverLength = await File(songs[0].coverUrl!).length();
      expect(coverLength, 400 * 1024 + 2);
    });
  });
}

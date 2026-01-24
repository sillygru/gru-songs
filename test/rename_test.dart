import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/file_manager_service.dart';
import 'package:gru_songs/services/api_service.dart';
import 'package:gru_songs/services/database_service.dart';
import 'package:gru_songs/models/song.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class ManualMockApiService extends ApiService {
  String? lastOld;

  String? lastNew;

  int? lastCount;

  String? lastType;

  bool renameCalled = false;

  @override
  Future<void> renameFile(String oldFilename, String newName, int deviceCount,
      {String? album, String? artist, String type = "file"}) async {
    lastOld = oldFilename;
    lastNew = newName;
    lastCount = deviceCount;
    lastType = type;
    renameCalled = true;
  }

  @override
  Future<List<dynamic>> getPendingRenames() async => [];
}

class ManualMockDatabaseService extends DatabaseService {
  String? lastOld;
  String? lastNew;
  bool renameCalled = false;

  ManualMockDatabaseService() : super.forTest();

  @override
  Future<void> renameFile(String oldFilename, String newFilename) async {
    lastOld = oldFilename;
    lastNew = newFilename;
    renameCalled = true;
  }
}

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

  group('FileManagerService Tests', () {
    late FileManagerService fileManagerService;
    late ManualMockApiService mockApiService;
    late ManualMockDatabaseService mockDatabaseService;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockApiService = ManualMockApiService();
      mockDatabaseService = ManualMockDatabaseService();
      DatabaseService.instance = mockDatabaseService;
      fileManagerService = FileManagerService(mockApiService);
      tempDir = await Directory.systemTemp.createTemp('rename_test');
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('renameSong renames file on filesystem', () async {
      final oldFile = File(p.join(tempDir.path, 'old.mp3'));
      await oldFile.writeAsString('dummy');

      final song = Song(
        title: 'Old',
        artist: 'Artist',
        album: 'Album',
        filename: 'old.mp3',
        url: oldFile.path,
      );

      await fileManagerService.renameSong(song, 'New');

      final newFile = File(p.join(tempDir.path, 'New.mp3'));
      expect(await oldFile.exists(), false);
      expect(await newFile.exists(), true);

      expect(mockApiService.renameCalled, true);
      expect(mockApiService.lastOld, 'old.mp3');
      expect(mockApiService.lastNew, 'New.mp3');
    });

    test('renameSong throws if target exists', () async {
      final oldFile = File(p.join(tempDir.path, 'old.mp3'));
      await oldFile.writeAsString('dummy');

      final targetFile = File(p.join(tempDir.path, 'New.mp3'));
      await targetFile.writeAsString('exists');

      final song = Song(
        title: 'Old',
        artist: 'Artist',
        album: 'Album',
        filename: 'old.mp3',
        url: oldFile.path,
      );

      expect(() => fileManagerService.renameSong(song, 'New'), throwsException);
    });
  });
}

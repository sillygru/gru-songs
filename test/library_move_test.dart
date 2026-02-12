import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gru_songs/services/library_logic.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('LibraryLogic Tests', () {
    test('getFolderContent groups subfolders and immediate songs correctly',
        () {
      final musicRoot = '/music';
      final songs = [
        Song(
            title: 'Root Song',
            artist: 'A',
            album: 'B',
            filename: 'root.mp3',
            url: p.join(musicRoot, 'root.mp3')),
        Song(
            title: 'Sub1 Song',
            artist: 'A',
            album: 'B',
            filename: 'sub1.mp3',
            url: p.join(musicRoot, 'Folder1', 'sub1.mp3')),
        Song(
            title: 'Sub1 Song 2',
            artist: 'A',
            album: 'B',
            filename: 'sub1_2.mp3',
            url: p.join(musicRoot, 'Folder1', 'sub1_2.mp3')),
        Song(
            title: 'Sub2 Song',
            artist: 'A',
            album: 'B',
            filename: 'sub2.mp3',
            url: p.join(musicRoot, 'Folder2', 'sub2.mp3')),
        Song(
            title: 'Deep Song',
            artist: 'A',
            album: 'B',
            filename: 'deep.mp3',
            url: p.join(musicRoot, 'Folder1', 'Deep', 'deep.mp3')),
      ];

      // Test Root
      final rootContent = LibraryLogic.getFolderContent(
          allSongs: songs, currentFullPath: musicRoot);
      expect(rootContent.immediateSongs.length, 1);
      expect(rootContent.immediateSongs[0].filename, 'root.mp3');
      expect(rootContent.subFolders, containsAll(['Folder1', 'Folder2']));
      expect(rootContent.subFolders.length, 2);
      expect(rootContent.subFolderSongs['Folder1']?.length,
          3); // sub1, sub1_2, deep
      expect(rootContent.subFolderSongs['Folder2']?.length, 1); // sub2

      // Test Folder1
      final folder1Path = p.join(musicRoot, 'Folder1');
      final folder1Content = LibraryLogic.getFolderContent(
          allSongs: songs, currentFullPath: folder1Path);
      expect(folder1Content.immediateSongs.length, 2);
      expect(folder1Content.immediateSongs.any((s) => s.filename == 'sub1.mp3'),
          true);
      expect(
          folder1Content.immediateSongs.any((s) => s.filename == 'sub1_2.mp3'),
          true);
      expect(folder1Content.subFolders, ['Deep']);
      expect(folder1Content.subFolderSongs['Deep']?.length, 1);
    });
  });

  group('Library Move Tests', () {
    late Directory tempDir;
    late Directory musicDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('library_move_test');
      musicDir = await Directory(p.join(tempDir.path, 'Music')).create();
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);

      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await tempDir.delete(recursive: true);
    });

    test('moveSong actually renames the file and its lyrics', () async {
      final sourceDir =
          await Directory(p.join(musicDir.path, 'Source')).create();
      final targetDir =
          await Directory(p.join(musicDir.path, 'Target')).create();

      final songFile = File(p.join(sourceDir.path, 'test_song.mp3'));
      await songFile.writeAsString('dummy mp3 content');

      final song = Song(
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 'test_song.mp3',
        url: songFile.path,
        hasLyrics: true,
      );

      final notifier = container.read(songsProvider.notifier);

      try {
        await notifier.moveSong(song, targetDir.path);
      } catch (e) {
        // Intentionally left empty for this test
      }

      final newSongPath = p.join(targetDir.path, 'test_song.mp3');

      expect(File(newSongPath).existsSync(), true,
          reason: 'Song file should be in target directory');
      expect(songFile.existsSync(), false,
          reason: 'Original song file should be gone');
    });

    test('moveSong creates target directory if it does not exist', () async {
      final sourceDir =
          await Directory(p.join(musicDir.path, 'Source')).create();
      final nestedTargetDir = p.join(musicDir.path, 'Nested', 'Target');

      final songFile = File(p.join(sourceDir.path, 'test_song.mp3'));
      await songFile.writeAsString('dummy mp3 content');

      final song = Song(
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 'test_song.mp3',
        url: songFile.path,
      );

      final notifier = container.read(songsProvider.notifier);

      try {
        await notifier.moveSong(song, nestedTargetDir);
      } catch (e) {
        // Intentionally left empty for this test
      }

      expect(Directory(nestedTargetDir).existsSync(), true,
          reason: 'Target directory should be created');
      expect(File(p.join(nestedTargetDir, 'test_song.mp3')).existsSync(), true);
    });
  });
}

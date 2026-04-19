import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gru_songs/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService folder metadata', () {
    late StorageService storageService;

    setUp(() {
      storageService = StorageService();
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips new folder metadata fields', () async {
      await storageService.addMusicFolder(
        '/music',
        'content://tree-uri',
        iosBookmarkId: 'bookmark-1',
        platform: 'ios',
      );

      final prefs = await SharedPreferences.getInstance();
      final folders = prefs.getStringList('music_folders_list')!;
      final saved = jsonDecode(folders.first) as Map<String, dynamic>;

      expect(saved['path'], '/music');
      expect(saved['treeUri'], 'content://tree-uri');
      expect(saved['platform'], 'ios');
      expect(saved['iosBookmarkId'], 'bookmark-1');

      final loaded = await storageService.getMusicFolders(forceRefresh: true);
      expect(loaded.single['path'], '/music');
      expect(loaded.single['treeUri'], 'content://tree-uri');
      expect(loaded.single['platform'], 'ios');
      expect(loaded.single['iosBookmarkId'], 'bookmark-1');
    });

    test('decodes legacy raw folder entries', () async {
      SharedPreferences.setMockInitialValues({
        'music_folders_list': ['/legacy/music'],
      });

      final loaded = await storageService.getMusicFolders(forceRefresh: true);
      expect(loaded.single['path'], '/legacy/music');
      expect(loaded.single['treeUri'], '');
    });

    test('removes folders by bookmark id when provided', () async {
      await storageService.addMusicFolder(
        '/music',
        null,
        iosBookmarkId: 'bookmark-2',
        platform: 'ios',
      );

      await storageService.removeMusicFolder(
        '/music',
        iosBookmarkId: 'bookmark-2',
      );

      final loaded = await storageService.getMusicFolders(forceRefresh: true);
      expect(loaded, isEmpty);
    });
  });
}

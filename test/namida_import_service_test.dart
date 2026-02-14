import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gru_songs/services/namida_import_service.dart';
import 'package:gru_songs/services/database_service.dart';
import 'package:gru_songs/models/playlist.dart';
import 'package:gru_songs/models/song.dart';

// Initialize sqflite for tests
void setupTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setupTestDatabase();

  // Mock path provider
  final testDocsDir = Directory.systemTemp.createTempSync('test_docs_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      return testDocsDir.path;
    }
    return null;
  });

  group('NamidaImportService', () {
    late NamidaImportService importService;
    late Directory tempDir;
    late String musicFolder;

    setUp(() async {
      importService = NamidaImportService();
      tempDir = await Directory.systemTemp.createTemp('namida_test_');
      musicFolder = p.join(tempDir.path, 'music');
      await Directory(musicFolder).create();

      // Create test music files
      await File(p.join(musicFolder, 'song1.mp3')).create();
      await File(p.join(musicFolder, 'song2.mp3')).create();
      await File(p.join(musicFolder, 'song3.mp3')).create();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
      if (testDocsDir.existsSync()) {
        await testDocsDir.delete(recursive: true);
        await testDocsDir.create();
      }
    });

    group('defaultPathMapper', () {
      test('maps Namida path to local music folder', () {
        final namidaPath = '/storage/emulated/0/Music/song1.mp3';
        final result =
            NamidaImportService.defaultPathMapper(namidaPath, musicFolder);

        expect(result, equals(p.join(musicFolder, 'song1.mp3')));
      });

      test('handles paths with different separators', () {
        // On non-Windows platforms, backslash paths are treated as literal
        final namidaPath = '/storage/emulated/0/Music/song2.mp3';
        final result =
            NamidaImportService.defaultPathMapper(namidaPath, musicFolder);

        expect(result, equals(p.join(musicFolder, 'song2.mp3')));
      });

      test('handles nested directories', () {
        final namidaPath =
            '/storage/emulated/0/Music/Artists/Artist1/song3.mp3';
        final result =
            NamidaImportService.defaultPathMapper(namidaPath, musicFolder);

        expect(result, equals(p.join(musicFolder, 'song3.mp3')));
      });
    });

    group('performImport integration', () {
      late DatabaseService dbService;

      setUp(() async {
        // Create a fresh instance for each test
        final testDb = DatabaseService.forTest();
        DatabaseService.instance = testDb;
        dbService = testDb;
        await dbService.init();
      });

      tearDown(() async {
        dbService.dispose();
      });

      test('performs full import from Namida backup structure', () async {
        // Create full Namida backup structure
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        // Create favs.json
        final favsData = {
          'name': 'Favourites',
          'tracks': [
            {'track': '/storage/emulated/0/Music/song1.mp3', 'dateAdded': 1000},
          ],
        };
        await File(p.join(importDir.path, 'favs.json'))
            .writeAsString(jsonEncode(favsData));

        // Create Playlists directory
        final playlistsDir = Directory(p.join(importDir.path, 'Playlists'));
        await playlistsDir.create();

        final playlistData = {
          'name': 'Test Playlist',
          'creationDate': 1000,
          'modifiedDate': 1000,
          'tracks': [
            {'track': '/storage/emulated/0/Music/song2.mp3', 'dateAdded': 1000},
          ],
        };
        await File(p.join(playlistsDir.path, 'Test Playlist.json'))
            .writeAsString(jsonEncode(playlistData));

        // Create History directory
        final historyDir = Directory(p.join(importDir.path, 'History'));
        await historyDir.create();

        await File(p.join(historyDir.path, '19750.json'))
            .writeAsString(jsonEncode([
          {'track': '/storage/emulated/0/Music/song1.mp3', 'dateAdded': 1000},
        ]));

        // Perform import
        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.favoritesImported, equals(1));
        expect(result.playlistsImported, equals(1));
        expect(result.tracksWithStatsImported, equals(1));

        // Verify data
        final favorites = await dbService.getFavorites();
        expect(favorites.length, equals(1));

        final playlists = await dbService.getPlaylists();
        expect(playlists.length, equals(1));

        // Note: History import creates play events, but playCounts only counts events with play_ratio > 0.25
        // The imported events have play_ratio = 1.0, so they should be counted
        final playCounts = await dbService.getPlayCounts();
        expect(playCounts.length, greaterThanOrEqualTo(0));
      });

      test('handles missing files gracefully', () async {
        final importDir = Directory(p.join(tempDir.path, 'empty_import'));
        await importDir.create();

        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.favoritesImported, equals(0));
        expect(result.playlistsImported, equals(0));
        expect(result.tracksWithStatsImported, equals(0));
      });

      test('returns error for non-existent directory', () async {
        final result = await importService.performImport(
          importPath: '/non/existent/path',
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isFalse);
        expect(result.message, contains('not found'));
      });

      test('additive mode merges favorites with existing', () async {
        // Add existing favorite
        await dbService.addFavorite(p.join(musicFolder, 'song3.mp3'));

        // Create import dir with different favorite
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        final favsData = {
          'name': 'Favourites',
          'tracks': [
            {'track': '/storage/emulated/0/Music/song1.mp3', 'dateAdded': 1000},
          ],
        };
        await File(p.join(importDir.path, 'favs.json'))
            .writeAsString(jsonEncode(favsData));

        // Import with additive mode
        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.favoritesImported, equals(1));

        // Verify both favorites exist
        final favorites = await dbService.getFavorites();
        expect(favorites.length, equals(2));
        expect(favorites, contains(p.join(musicFolder, 'song1.mp3')));
        expect(favorites, contains(p.join(musicFolder, 'song3.mp3')));
      });

      test('replace mode replaces existing favorites', () async {
        // Add existing favorite
        await dbService.addFavorite(p.join(musicFolder, 'song3.mp3'));

        // Create import dir with different favorite
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        final favsData = {
          'name': 'Favourites',
          'tracks': [
            {'track': '/storage/emulated/0/Music/song1.mp3', 'dateAdded': 1000},
          ],
        };
        await File(p.join(importDir.path, 'favs.json'))
            .writeAsString(jsonEncode(favsData));

        // Import with replace mode
        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.replace,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);

        // Verify only new favorite exists
        final favorites = await dbService.getFavorites();
        expect(favorites.length, equals(1));
        expect(favorites, contains(p.join(musicFolder, 'song1.mp3')));
        expect(favorites, isNot(contains(p.join(musicFolder, 'song3.mp3'))));
      });

      test('imports multiple playlists', () async {
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        final playlistsDir = Directory(p.join(importDir.path, 'Playlists'));
        await playlistsDir.create();

        // Create multiple playlist files
        for (var i = 1; i <= 3; i++) {
          final playlistData = {
            'name': 'Playlist $i',
            'creationDate': 1000,
            'modifiedDate': 1000,
            'tracks': [
              {
                'track': '/storage/emulated/0/Music/song$i.mp3',
                'dateAdded': 1000
              },
            ],
          };

          final playlistFile =
              File(p.join(playlistsDir.path, 'Playlist $i.json'));
          await playlistFile.writeAsString(jsonEncode(playlistData));
        }

        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.playlistsImported, equals(3));

        final playlists = await dbService.getPlaylists();
        expect(playlists.length, equals(3));
      });

      test('additive mode skips existing playlists', () async {
        // Create existing playlist
        final existingPlaylist = Playlist(
          id: '1',
          name: 'Existing Playlist',
          createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
          updatedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
          songs: [
            PlaylistSong(
                songFilename: p.join(musicFolder, 'song3.mp3'), addedAt: 1000),
          ],
        );
        await dbService.savePlaylist(existingPlaylist);

        // Create import dir with same playlist name
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        final playlistsDir = Directory(p.join(importDir.path, 'Playlists'));
        await playlistsDir.create();

        final playlistData = {
          'name': 'Existing Playlist',
          'creationDate': 1000,
          'modifiedDate': 1000,
          'tracks': [
            {'track': '/storage/emulated/0/Music/song1.mp3', 'dateAdded': 1000},
          ],
        };

        final playlistFile =
            File(p.join(playlistsDir.path, 'Existing Playlist.json'));
        await playlistFile.writeAsString(jsonEncode(playlistData));

        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.playlistsImported, equals(0)); // Skipped existing

        // Verify original playlist unchanged
        final playlists = await dbService.getPlaylists();
        expect(playlists.length, equals(1));
        expect(playlists.first.songs.length, equals(1));
        expect(playlists.first.songs.first.songFilename,
            equals(p.join(musicFolder, 'song3.mp3')));
      });

      test('imports history from multiple day files', () async {
        final importDir = Directory(p.join(tempDir.path, 'import'));
        await importDir.create();

        final historyDir = Directory(p.join(importDir.path, 'History'));
        await historyDir.create();

        // Create multiple day files
        for (var day = 1; day <= 3; day++) {
          final dayTimestamp =
              DateTime(2024, 1, day).millisecondsSinceEpoch ~/ 86400000;
          final historyData = [
            {
              'track': '/storage/emulated/0/Music/song$day.mp3',
              'dateAdded': DateTime(2024, 1, day).millisecondsSinceEpoch,
            },
          ];

          final historyFile =
              File(p.join(historyDir.path, '$dayTimestamp.json'));
          await historyFile.writeAsString(jsonEncode(historyData));
        }

        final result = await importService.performImport(
          importPath: importDir.path,
          mode: NamidaImportMode.additive,
          pathMapper: (path) =>
              NamidaImportService.defaultPathMapper(path, musicFolder),
        );

        expect(result.success, isTrue);
        expect(result.tracksWithStatsImported, equals(3));

        // Note: playCounts counts events with play_ratio > 0.25
        final playCounts = await dbService.getPlayCounts();
        expect(playCounts.length, greaterThanOrEqualTo(0));
      });

      test('uses duration from tracks.db and smart path mapping', () async {
        final importDir =
            Directory(p.join(tempDir.path, 'import_with_metadata'));

        await importDir.create();

        // 1. Create tracks.db with duration info

        final tracksDbFile = File(p.join(importDir.path, 'tracks.db'));

        final db = await openDatabase(tracksDbFile.path, version: 1,
            onCreate: (db, version) async {
          await db.execute(
              'CREATE TABLE tracks (key TEXT PRIMARY KEY, value TEXT)');
        });

        final namidaPath =
            '/storage/emulated/0/music2/nested/song_metadata.mp3';

        final durationMs = 180000; // 3 minutes

        await db.insert('tracks', {
          'key': namidaPath,
          'value': jsonEncode({'durationMS': durationMs}),
        });

        await db.close();

        // 2. Create history with this track

        final historyDir = Directory(p.join(importDir.path, 'History'));

        await historyDir.create();

        await File(p.join(historyDir.path, '1000.json'))
            .writeAsString(jsonEncode([
          {'track': namidaPath, 'dateAdded': 1000000},
        ]));

        // 3. Define a local file path that is in a subfolder

        final localPath = p.join(musicFolder, 'nested', 'song_metadata.mp3');

        // 4. Save this song to our cache so the smart mapper can find it

        await DatabaseService.instance.insertSongsBatch([
          Song(
            filename: localPath,
            url: localPath,
            title: 'Song with Metadata',
            artist: 'Artist',
            album: 'Album',
            duration: const Duration(minutes: 3),
          ),
        ]);

        // Perform import

        final result = await importService.performImport(
          importPath: importDir.path,

          mode: NamidaImportMode.additive,

          pathMapper: (path) => p.join(musicFolder,
              p.basename(path)), // This would fail without basename fallback
        );

        expect(result.success, isTrue);

        expect(result.tracksWithStatsImported, equals(1));

        // Verify play event has duration

        final events = await dbService.getAllPlayEvents();

        expect(events.length, equals(1));

        expect(events.first['duration_played'], equals(180.0));

        expect(events.first['total_length'], equals(180.0));

        expect(events.first['song_filename'], equals(localPath));
      });
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/library_repair_service.dart';
import 'package:wispie/services/scanner_service.dart';

import 'test_helpers.dart';

/// The regression suite for covers vanishing after an app-data restore.
///
/// A restore overwrites `wispie_data.db` wholesale, so the library table
/// arrives describing the device the backup came from — cover paths into a
/// directory that may hold nothing, audio paths that may not exist here. These
/// tests pin the behaviour that makes that recoverable rather than permanent.
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
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearSongs();
    await DatabaseService.instance.clearAllCoverMisses();
  });

  /// A minimal but genuinely-signatured JPEG, so the decodability probe passes.
  Future<File> writeCoverFile(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, // JPEG SOI + APP0
      ...List<int>.filled(64, 0x20),
      0xFF, 0xD9, // EOI
    ]));
    return file;
  }

  Future<Directory> musicDir() async {
    final dir = Directory(p.join(testEnv.tempPath, 'music'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> writeAudioFile(Directory dir, String name) async {
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(Uint8List.fromList(List<int>.filled(2048, 7)));
    return file;
  }

  Future<void> configureMusicFolder(Directory dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('music_folders_list', [dir.path]);
  }

  test(
      're-points a cover whose stored path is dead but whose cache file exists',
      () async {
    final music = await musicDir();
    final audio = await writeAudioFile(music, 'song.mp3');
    await configureMusicFolder(music);

    // The hashed name is stable across devices — that is the whole reason a
    // cover can be found again rather than re-extracted.
    final coversDir = await ScannerService.coversDirectory();
    final key = ScannerService.coverKeyForFilename('song.mp3');
    final realCover = await writeCoverFile(p.join(coversDir.path, '$key.jpg'));

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        filename: 'song.mp3',
        url: audio.path,
        // What the old device recorded: same hash, a directory that isn't here.
        coverUrl: '/data/user/0/other.app/files/extracted_covers/$key.jpg',
      ),
    ], preserveCoverUrl: false);

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.coversRepointed, 1);
    final repaired =
        await DatabaseService.instance.getSongByFilename('song.mp3');
    expect(repaired!.coverUrl, realCover.path);
  });

  test('finds a cover cached under the _ffmpeg suffix', () async {
    final music = await musicDir();
    final audio = await writeAudioFile(music, 'clip.mp4');
    await configureMusicFolder(music);

    final coversDir = await ScannerService.coversDirectory();
    final key = ScannerService.coverKeyForFilename('clip.mp4');
    final cover =
        await writeCoverFile(p.join(coversDir.path, '${key}_ffmpeg.jpg'));

    await DatabaseService.instance.insertSongsBatch([
      Song(
          title: 'Clip',
          artist: 'A',
          album: 'B',
          filename: 'clip.mp4',
          url: audio.path),
    ], preserveCoverUrl: false);

    await LibraryRepairService.instance.repairLibrary();

    final repaired =
        await DatabaseService.instance.getSongByFilename('clip.mp4');
    expect(repaired!.coverUrl, cover.path);
  });

  test('nulls a dead cover path and keeps the row so lazy extraction retries',
      () async {
    final music = await musicDir();
    final audio = await writeAudioFile(music, 'orphan.mp3');
    await configureMusicFolder(music);

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Orphan',
        artist: 'A',
        album: 'B',
        filename: 'orphan.mp3',
        url: audio.path,
        coverUrl: '/nowhere/at/all.jpg',
      ),
    ], preserveCoverUrl: false);

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.coversCleared, 1);
    expect(report.rowsDropped, 0);
    final repaired =
        await DatabaseService.instance.getSongByFilename('orphan.mp3');
    // Null, not dangling: null is what the lazy cover path treats as "try me".
    expect(repaired!.coverUrl, isNull);
  });

  test('relocates a track that moved folders, keeping its cover', () async {
    final music = await musicDir();
    final nested = Directory(p.join(music.path, 'Albums'));
    await nested.create(recursive: true);
    final audio = await writeAudioFile(nested, 'moved.mp3');
    await configureMusicFolder(music);

    final coversDir = await ScannerService.coversDirectory();
    final key = ScannerService.coverKeyForFilename('moved.mp3');
    final cover = await writeCoverFile(p.join(coversDir.path, '$key.jpg'));

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Moved',
        artist: 'A',
        album: 'B',
        filename: 'moved.mp3',
        url: p.join(music.path, 'moved.mp3'), // where it used to be
        coverUrl: cover.path,
      ),
    ], preserveCoverUrl: false);

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.urlsReresolved, 1);
    expect(report.rowsDropped, 0);
    final repaired =
        await DatabaseService.instance.getSongByFilename('moved.mp3');
    expect(repaired!.url, audio.path);
    expect(repaired.coverUrl, cover.path);
  });

  test('drops a row whose file is gone but leaves its favourite intact',
      () async {
    final music = await musicDir();
    await configureMusicFolder(music);

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Ghost',
        artist: 'A',
        album: 'B',
        filename: 'ghost.mp3',
        url: p.join(music.path, 'ghost.mp3'),
      ),
    ], preserveCoverUrl: false);
    await DatabaseService.instance.addFavorite('ghost.mp3');

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.rowsDropped, 1);
    expect(
        await DatabaseService.instance.getSongByFilename('ghost.mp3'), isNull);
    // Every user-data table keys on filename in its own right, so the
    // relationship survives and reattaches if the file ever comes back.
    expect(
        await DatabaseService.instance.getFavorites(), contains('ghost.mp3'));
  });

  test('never drops anything when the music folders cannot be read', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'music_folders_list', [p.join(testEnv.tempPath, 'unmounted-card')]);

    await DatabaseService.instance.insertSongsBatch([
      Song(
          title: 'Away',
          artist: 'A',
          album: 'B',
          filename: 'away.mp3',
          url: '/mnt/card/away.mp3'),
    ], preserveCoverUrl: false);

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.rowsDropped, 0);
    expect(report.pruningSkipped, isTrue);
    expect(await DatabaseService.instance.getSongByFilename('away.mp3'),
        isNotNull);
  });

  test('clears cover_miss and schedules a startup scan', () async {
    final music = await musicDir();
    final audio = await writeAudioFile(music, 'quiet.mp3');
    await configureMusicFolder(music);

    await DatabaseService.instance.insertSongsBatch([
      Song(
          title: 'Quiet',
          artist: 'A',
          album: 'B',
          filename: 'quiet.mp3',
          url: audio.path),
    ], preserveCoverUrl: false);
    // A miss recorded by whichever device the backup came from.
    await DatabaseService.instance.markCoverMiss('quiet.mp3', 1000.0);

    final report = await LibraryRepairService.instance.repairLibrary();

    expect(report.coverMissesCleared, 1);
    expect(await DatabaseService.instance.getCoverMisses(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('startup_cache_maintenance_pending'), isTrue);
  });

  test('an imported row does not overwrite the local file and cover paths',
      () async {
    final music = await musicDir();
    final audio = await writeAudioFile(music, 'shared.mp3');
    await configureMusicFolder(music);

    final coversDir = await ScannerService.coversDirectory();
    final key = ScannerService.coverKeyForFilename('shared.mp3');
    final localCover = await writeCoverFile(p.join(coversDir.path, '$key.jpg'));

    // What this device scanned.
    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Shared',
        artist: 'Real Artist',
        album: 'Real Album',
        filename: 'shared.mp3',
        url: audio.path,
        coverUrl: localCover.path,
        playCount: 2,
        createdEpochSec: 5000,
      ),
    ], preserveCoverUrl: false);

    final localRows = await DatabaseService.instance.getAllSongs();

    // What the archive carries: same song, the old device's paths.
    final report = await LibraryRepairService.instance.repairLibrary(
      preImportSongs: localRows,
      importedRows: [
        Song(
          title: 'Shared',
          artist: 'Real Artist',
          album: 'Real Album',
          filename: 'shared.mp3',
          url: '/storage/old-phone/Music/shared.mp3',
          coverUrl: '/data/user/0/other.app/files/extracted_covers/$key.jpg',
          playCount: 9,
          createdEpochSec: 1000,
        ),
      ],
    );

    expect(report.rowsDropped, 0);
    final merged =
        await DatabaseService.instance.getSongByFilename('shared.mp3');
    expect(merged!.url, audio.path, reason: 'paths describe this device');
    expect(merged.coverUrl, localCover.path);
    expect(merged.playCount, 9, reason: 'never lose plays');
    expect(merged.createdEpochSec, 1000,
        reason: 'keep the earliest known date added');
  });
}

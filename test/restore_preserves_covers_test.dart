import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/backup_service.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/import_options.dart';
import 'package:wispie/services/scanner_service.dart';

import 'test_helpers.dart';

/// End-to-end cover for the reported bug: songs imported and scanned on a new
/// phone showed their artwork, then importing the app-data backup made most of
/// it disappear.
///
/// The restore replaces `wispie_data.db` outright, and the `song` table lives
/// inside it — so the rows this device had just scanned, with their real file
/// paths and freshly extracted covers, were overwritten by the old device's
/// rows. No import category names `song`, so nothing warned and nothing put it
/// back.
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final backupsDir = Directory(p.join(testEnv.tempPath, 'backups'));
    if (await backupsDir.exists()) await backupsDir.delete(recursive: true);

    await DatabaseService.instance.init();
    await DatabaseService.instance.clearSongs();
    await DatabaseService.instance.clearAllCoverMisses();
  });

  BackupInfo backupInfoFor(String filename) {
    final file = File(p.join(testEnv.tempPath, 'backups', filename));
    return BackupInfo(
      number: 1,
      timestamp: DateTime.now(),
      filename: filename,
      file: file,
      sizeBytes: file.lengthSync(),
    );
  }

  test('a restore keeps the covers this device extracted', () async {
    // --- The new phone: music copied over, scanned, covers extracted. ---
    final music = Directory(p.join(testEnv.tempPath, 'music'));
    await music.create(recursive: true);
    final audio = File(p.join(music.path, 'song.mp3'));
    await audio.writeAsBytes(Uint8List.fromList(List<int>.filled(4096, 9)));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('music_folders_list', [music.path]);

    final coversDir = await ScannerService.coversDirectory();
    final key = ScannerService.coverKeyForFilename('song.mp3');
    final cover = File(p.join(coversDir.path, '$key.jpg'));
    await cover.writeAsBytes(Uint8List.fromList(
        [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.filled(32, 0), 0xFF, 0xD9]));

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        filename: 'song.mp3',
        url: audio.path,
        coverUrl: cover.path,
      ),
    ], preserveCoverUrl: false);

    // --- The old phone's backup: same song, but no cover was ever extracted
    //     there, plus a favourite that is the whole reason to restore. ---
    await DatabaseService.instance.clearSongs();
    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        filename: 'song.mp3',
        url: '/storage/emulated/0/OldPhone/song.mp3',
        coverUrl: null,
      ),
    ], preserveCoverUrl: false);
    await DatabaseService.instance.addFavorite('song.mp3');

    final backupFilename = await BackupService.instance.createBackup(
      BackupOptions(contentTypes: {
        BackupContentType.userData,
        BackupContentType.userStats,
      }),
    );

    // --- Back to the new phone's state, then restore on top of it. ---
    await DatabaseService.instance.clearSongs();
    await DatabaseService.instance.removeFavorite('song.mp3');
    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        filename: 'song.mp3',
        url: audio.path,
        coverUrl: cover.path,
      ),
    ], preserveCoverUrl: false);

    await BackupService.instance.restoreFromBackup(
      backupInfoFor(backupFilename),
      options: ImportOptions.defaultImport,
    );

    // The point of the restore still works…
    expect(await DatabaseService.instance.getFavorites(), contains('song.mp3'));

    // …and the artwork this device extracted is still there and still resolves.
    final restored =
        await DatabaseService.instance.getSongByFilename('song.mp3');
    expect(restored, isNotNull);
    expect(restored!.coverUrl, isNotNull,
        reason: 'the old device\'s null must not erase a working cover');
    expect(File(restored.coverUrl!).existsSync(), isTrue);
    expect(restored.url, audio.path,
        reason: 'file paths must describe this device, not the archive');

    // A miss recorded elsewhere must not suppress extraction here.
    expect(await DatabaseService.instance.getCoverMisses(), isEmpty);
  });

  test('a restore carrying both databases completes instead of deadlocking',
      () async {
    // The category import opens the archive's databases as a second
    // connection. Pointing it at the files just written into the app directory
    // meant opening the database DatabaseService already holds, and the restore
    // hung on the first transaction — silently, with the spinner still up.
    await DatabaseService.instance.addFavorite('deadlock.mp3');

    final backupFilename = await BackupService.instance.createBackup(
      BackupOptions(contentTypes: {
        BackupContentType.userData,
        BackupContentType.userStats,
      }),
    );

    await DatabaseService.instance.removeFavorite('deadlock.mp3');

    await BackupService.instance.restoreFromBackup(
      backupInfoFor(backupFilename),
      options: ImportOptions.defaultImport,
    );

    expect(await DatabaseService.instance.getFavorites(),
        contains('deadlock.mp3'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

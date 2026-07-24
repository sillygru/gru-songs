import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wispie/models/song.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/scanner_service.dart';

import '../test_helpers.dart';

/// The scanner reconciles against existing rows by path, but the `song` table's
/// primary key is the basename. Where those two disagree, a file that merely
/// moved folders looked brand new, took the fast-scan branch — which writes no
/// cover, no metadata and no date-added — and then replaced the row it should
/// have matched.
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
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearSongs();
  });

  Future<File> writeAudio(Directory dir, String name) async {
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(Uint8List.fromList(List<int>.filled(4096, 1)));
    return file;
  }

  test('a file that moved folders keeps its cover, metadata and date added',
      () async {
    final root = Directory(p.join(testEnv.tempPath, 'lib_moved'));
    final nested = Directory(p.join(root.path, 'Albums'));
    final audio = await writeAudio(nested, 'moved.mp3');

    final existing = Song(
      title: 'Real Title',
      artist: 'Real Artist',
      album: 'Real Album',
      filename: 'moved.mp3',
      url: p.join(root.path, 'moved.mp3'), // the folder it used to be in
      coverUrl: '/covers/moved.jpg',
      playCount: 4,
      createdEpochSec: 1000,
      mtime: 1.0, // deliberately stale, to force the non-reuse branch
    );

    final result = await ScannerService().scanDirectory(
      root.path,
      existingSongs: [existing],
      fastMode: true,
    );

    final scanned = result.songs.firstWhere((s) => s.filename == 'moved.mp3');
    expect(scanned.url, audio.path, reason: 'points at where the file is now');
    expect(scanned.coverUrl, '/covers/moved.jpg');
    expect(scanned.title, 'Real Title');
    expect(scanned.artist, 'Real Artist');
    expect(scanned.playCount, 4);
    expect(scanned.createdEpochSec, 1000);
  });

  test('an mtime nudge does not reset a row to placeholders', () async {
    final root = Directory(p.join(testEnv.tempPath, 'lib_touched'));
    final audio = await writeAudio(root, 'touched.mp3');

    final existing = Song(
      title: 'Enriched',
      artist: 'Known Artist',
      album: 'Known Album',
      filename: 'touched.mp3',
      url: audio.path,
      coverUrl: '/covers/touched.jpg',
      createdEpochSec: 2000,
      mtime: 1.0,
    );

    final result = await ScannerService().scanDirectory(
      root.path,
      existingSongs: [existing],
      fastMode: true,
    );

    final scanned = result.songs.firstWhere((s) => s.filename == 'touched.mp3');
    expect(scanned.coverUrl, '/covers/touched.jpg');
    expect(scanned.artist, 'Known Artist');
    expect(scanned.createdEpochSec, 2000);
  });

  test('a genuinely new file still gets a placeholder row', () async {
    final root = Directory(p.join(testEnv.tempPath, 'lib_new'));
    await writeAudio(root, 'brand_new.mp3');

    final result = await ScannerService().scanDirectory(
      root.path,
      existingSongs: const [],
      fastMode: true,
    );

    final scanned =
        result.songs.firstWhere((s) => s.filename == 'brand_new.mp3');
    expect(scanned.artist, 'Unknown Artist');
    expect(scanned.coverUrl, isNull);
    expect(scanned.createdEpochSec, isNotNull);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/scanner_service.dart';

import 'test_helpers.dart';

/// Guards the changes that keep the first-startup scan off the UI thread:
/// metadata enrichment now runs in a background isolate, and songs with no
/// cover art are recorded so they are never probed twice.
void main() {
  late TestEnvironment testEnv;
  late Directory musicDir;

  setUpAll(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
    musicDir = Directory.systemTemp.createTempSync('wispie_music_');
    await DatabaseService.instance.init();
  });

  tearDownAll(() {
    if (musicDir.existsSync()) musicDir.deleteSync(recursive: true);
    testEnv.tearDown();
  });

  Song fastScanSong(String path) => Song(
        title: path.split(Platform.pathSeparator).last.split('.').first,
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        filename: path.split(Platform.pathSeparator).last,
        url: path,
        playCount: 0,
        mtime: 1000,
      );

  group('enrichAllMetadata', () {
    test('returns every song, in order, across isolate batch boundaries',
        () async {
      // More than one batch (batchSize is 50) so batch reassembly is covered.
      final songs = <Song>[];
      for (int i = 0; i < 120; i++) {
        final file = File('${musicDir.path}/track_$i.mp3')
          ..writeAsBytesSync(List<int>.filled(64, 0));
        songs.add(fastScanSong(file.path));
      }

      final result = await ScannerService.enrichAllMetadata(songs);

      expect(result.length, songs.length);
      expect(
        result.map((s) => s.url).toList(),
        songs.map((s) => s.url).toList(),
      );
    });

    test('passes through songs whose files are gone', () async {
      final missing = fastScanSong('${musicDir.path}/not_here.mp3');

      final result = await ScannerService.enrichAllMetadata([missing]);

      expect(result.single.url, missing.url);
      expect(result.single.title, missing.title);
      expect(result.single.artist, 'Unknown Artist');
    });

    test('reports progress up to 1.0', () async {
      final file = File('${musicDir.path}/progress.mp3')
        ..writeAsBytesSync(List<int>.filled(64, 0));

      final progress = <double>[];
      await ScannerService.enrichAllMetadata(
        [fastScanSong(file.path)],
        onProgress: progress.add,
      );

      expect(progress.last, 1.0);
    });
  });

  group('cover miss negative cache', () {
    test('round-trips through the database', () async {
      await DatabaseService.instance.markCoverMiss('no_art.mp3', 1234.0);

      final misses = await DatabaseService.instance.getCoverMisses();

      expect(misses['no_art.mp3'], 1234.0);
    });

    test('re-marking updates the recorded mtime rather than duplicating',
        () async {
      await DatabaseService.instance.markCoverMiss('edited.mp3', 1000.0);
      await DatabaseService.instance.markCoverMiss('edited.mp3', 2000.0);

      final misses = await DatabaseService.instance.getCoverMisses();

      expect(misses['edited.mp3'], 2000.0);
    });

    test('clearing removes the entry so the song is probed again', () async {
      await DatabaseService.instance.markCoverMiss('recheck.mp3', 1000.0);
      await DatabaseService.instance.clearCoverMiss('recheck.mp3');

      final misses = await DatabaseService.instance.getCoverMisses();

      expect(misses.containsKey('recheck.mp3'), isFalse);
    });
  });
}

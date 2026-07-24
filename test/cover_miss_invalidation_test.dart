import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wispie/models/song.dart';
import 'package:wispie/services/cover_refresh_service.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/scanner_service.dart';
import 'package:wispie/services/storage_analysis_service.dart';

import 'test_helpers.dart';

/// The negative cache exists so a song with genuinely no artwork isn't
/// re-probed on every list tile. It became a trap when a `cover_miss` row —
/// which travels inside a restored database — was treated as authoritative by
/// the widget gate, permanently suppressing extraction for songs this device
/// had never actually examined.
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
    await DatabaseService.instance.clearAllCoverMisses();
    CoverRefreshService.instance.invalidateMisses();
  });

  test('an inherited cover_miss row does not suppress the first probe',
      () async {
    // Exactly what a restore leaves behind: a miss another device recorded.
    await DatabaseService.instance.markCoverMiss('inherited.mp3', 1000.0);
    CoverRefreshService.instance.invalidateMisses();

    expect(CoverRefreshService.instance.isSuppressed('inherited.mp3'), isFalse,
        reason: 'the tile must still be allowed to schedule a probe');
  });

  test('a miss this process confirmed does suppress further probes', () async {
    final music = Directory(p.join(testEnv.tempPath, 'music'));
    await music.create(recursive: true);
    final audio = File(p.join(music.path, 'silent.mp3'));
    // Real bytes, but nothing an extractor can find artwork in.
    await audio.writeAsBytes(Uint8List.fromList(List<int>.filled(4096, 3)));

    await DatabaseService.instance.insertSongsBatch([
      Song(
          title: 'Silent',
          artist: 'A',
          album: 'B',
          filename: 'silent.mp3',
          url: audio.path),
    ]);

    final result =
        await CoverRefreshService.instance.ensureCoverForSong('silent.mp3');

    expect(result, isNull);
    expect(CoverRefreshService.instance.isSuppressed('silent.mp3'), isTrue);
    expect(await DatabaseService.instance.getCoverMisses(),
        contains('silent.mp3'));
  });

  test('forgetMisses re-opens a specific song', () async {
    await DatabaseService.instance.markCoverMiss('retry.mp3', 1000.0);
    CoverRefreshService.instance.invalidateMisses();

    await DatabaseService.instance.clearCoverMisses(['retry.mp3']);
    CoverRefreshService.instance.forgetMisses(['retry.mp3']);

    expect(await DatabaseService.instance.getCoverMisses(), isEmpty);
    expect(CoverRefreshService.instance.isSuppressed('retry.mp3'), isFalse);
  });

  test('clearing the cover cache also clears the paths pointing into it',
      () async {
    final coversDir = await ScannerService.coversDirectory();
    final cover = File(p.join(coversDir.path, 'some_cover.jpg'));
    await cover.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]));

    await DatabaseService.instance.insertSongsBatch([
      Song(
        title: 'T',
        artist: 'A',
        album: 'B',
        filename: 'has_cover.mp3',
        url: '/music/has_cover.mp3',
        coverUrl: cover.path,
      ),
    ]);
    await DatabaseService.instance.markCoverMiss('other.mp3', 1000.0);

    await StorageAnalysisService.instance.clearCoversCache();

    final stored =
        await DatabaseService.instance.getSongByFilename('has_cover.mp3');
    // Null rather than dangling, so lazy extraction picks it back up. Leaving
    // the path behind is what made "clear cover cache" look like a no-op.
    expect(stored!.coverUrl, isNull);
    expect(await DatabaseService.instance.getCoverMisses(), isEmpty);
  });
}

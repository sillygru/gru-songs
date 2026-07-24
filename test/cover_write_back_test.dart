import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/database_service.dart';
import 'package:wispie/services/scanner_service.dart';

import 'test_helpers.dart';

/// Pins the invariant that a *failure to resolve* a cover can never be written
/// as *there is no cover*.
///
/// Every path that erased artwork did so by treating null as a finding: a scan
/// that couldn't read a file, a rebuild that couldn't reach an unmounted card,
/// an import carrying another device's rows. The guard lives in the database
/// layer so no caller can forget it.
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

  Song song({String? coverUrl, double? createdEpochSec, int playCount = 0}) {
    return Song(
      title: 'Title',
      artist: 'Artist',
      album: 'Album',
      filename: 'track.mp3',
      url: '/music/track.mp3',
      coverUrl: coverUrl,
      playCount: playCount,
      createdEpochSec: createdEpochSec,
    );
  }

  test('a null cover does not erase an existing one', () async {
    await DatabaseService.instance
        .insertSongsBatch([song(coverUrl: '/covers/a.jpg')]);

    // The shape a fast scan or an unreadable file produces.
    await DatabaseService.instance.insertSongsBatch([song(coverUrl: null)]);

    final stored =
        await DatabaseService.instance.getSongByFilename('track.mp3');
    expect(stored!.coverUrl, '/covers/a.jpg');
  });

  test('a real new cover still replaces the old one', () async {
    await DatabaseService.instance
        .insertSongsBatch([song(coverUrl: '/covers/a.jpg')]);
    await DatabaseService.instance
        .insertSongsBatch([song(coverUrl: '/covers/b.jpg')]);

    final stored =
        await DatabaseService.instance.getSongByFilename('track.mp3');
    expect(stored!.coverUrl, '/covers/b.jpg');
  });

  test('preserveCoverUrl: false clears it, for the repair pass', () async {
    await DatabaseService.instance
        .insertSongsBatch([song(coverUrl: '/covers/a.jpg')]);
    await DatabaseService.instance
        .insertSongsBatch([song(coverUrl: null)], preserveCoverUrl: false);

    final stored =
        await DatabaseService.instance.getSongByFilename('track.mp3');
    expect(stored!.coverUrl, isNull);
  });

  test('created_epoch_sec survives a re-insert that omits it', () async {
    await DatabaseService.instance
        .insertSongsBatch([song(createdEpochSec: 1234)]);
    await DatabaseService.instance.insertSongsBatch([song()]);

    final stored =
        await DatabaseService.instance.getSongByFilename('track.mp3');
    expect(stored!.createdEpochSec, 1234);
  });

  test('other columns are still overwritten normally', () async {
    await DatabaseService.instance.insertSongsBatch([song(playCount: 3)]);
    await DatabaseService.instance.insertSongsBatch([song(playCount: 11)]);

    final stored =
        await DatabaseService.instance.getSongByFilename('track.mp3');
    expect(stored!.playCount, 11);
  });

  test('rebuildCoverCache reports nothing for a file it cannot read', () async {
    final result = await ScannerService().rebuildCoverCache([
      Song(
        title: 'Gone',
        artist: 'A',
        album: 'B',
        filename: 'gone.mp3',
        url: '${testEnv.tempPath}/definitely/not/here.mp3',
        coverUrl: '/covers/keep-me.jpg',
      ),
    ]);

    // Absent, not null — the caller can then tell "no cover" apart from
    // "couldn't look", and leaves the existing one alone.
    expect(result.containsKey('${testEnv.tempPath}/definitely/not/here.mp3'),
        isFalse);
  });

  test('the _ffmpeg suffix is a recognised cached cover', () {
    expect(ScannerService.coverExtensionCandidates, contains('_ffmpeg.jpg'));

    final candidates =
        ScannerService.coverCandidatePaths('/covers', 'video.mp4');
    final key = ScannerService.coverKeyForFilename('video.mp4');
    expect(candidates, contains('/covers/${key}_ffmpeg.jpg'));
  });
}

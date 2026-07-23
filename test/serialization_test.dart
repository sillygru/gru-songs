import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';

void main() {
  group('Serialization Tests', () {
    test('Song serialization round-trip', () {
      const song = Song(
        title: 'Test Title',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 'test.mp3',
        url: 'http://test.com/test.mp3',
        hasLyrics: true,
        coverUrl: 'http://test.com/cover',
        playCount: 10,
        duration: Duration(seconds: 120),
      );

      final json = song.toJson();
      final fromJson = Song.fromJson(json);

      expect(fromJson.title, song.title);
      expect(fromJson.artist, song.artist);
      expect(fromJson.playCount, song.playCount);
      // Precision might slightly differ due to double conversion, checking milliseconds
      expect(fromJson.duration?.inSeconds, song.duration?.inSeconds);
    });

    test('QueueItem serialization round-trip', () {
      const song = Song(
        title: 'Test Title',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 'test.mp3',
        url: 'http://test.com/test.mp3',
      );
      final item = QueueItem(song: song);

      final json = item.toJson();
      final fromJson = QueueItem.fromJson(json);

      expect(fromJson.song.filename, item.song.filename);
      expect(fromJson.queueId, item.queueId);
    });
  });

  group('Song.copyWith', () {
    const original = Song(
      title: 'Test Title',
      artist: 'Test Artist',
      album: 'Test Album',
      filename: 'test.mp3',
      url: '/music/test.mp3',
      coverUrl: '/covers/test.jpg',
      hasLyrics: true,
      playCount: 10,
      duration: Duration(seconds: 120),
      mtime: 1000.5,
      createdEpochSec: 900.0,
      songDateEpochSec: 800.0,
    );

    test('changes only what it is given', () {
      final updated = original.copyWith(title: 'New Title');

      expect(updated.title, 'New Title');
      expect(updated, original.copyWith(title: 'New Title'));
      // Everything else must survive — a dropped field here silently loses a
      // song's play count or date-added on every metadata edit.
      expect(updated.artist, original.artist);
      expect(updated.album, original.album);
      expect(updated.filename, original.filename);
      expect(updated.url, original.url);
      expect(updated.coverUrl, original.coverUrl);
      expect(updated.hasLyrics, original.hasLyrics);
      expect(updated.playCount, original.playCount);
      expect(updated.duration, original.duration);
      expect(updated.mtime, original.mtime);
      expect(updated.createdEpochSec, original.createdEpochSec);
      expect(updated.songDateEpochSec, original.songDateEpochSec);
    });

    test('an empty copy equals the original', () {
      expect(original.copyWith(), original);
    });

    test('every field can be replaced', () {
      final updated = original.copyWith(
        title: 'T',
        artist: 'A',
        album: 'B',
        filename: 'renamed.mp3',
        url: '/music/renamed.mp3',
        coverUrl: '/covers/renamed.jpg',
        hasLyrics: false,
        playCount: 3,
        duration: const Duration(seconds: 5),
        mtime: 2000.0,
        createdEpochSec: 1900.0,
        songDateEpochSec: 1800.0,
      );

      expect(updated.title, 'T');
      expect(updated.artist, 'A');
      expect(updated.album, 'B');
      expect(updated.filename, 'renamed.mp3');
      expect(updated.url, '/music/renamed.mp3');
      expect(updated.coverUrl, '/covers/renamed.jpg');
      expect(updated.hasLyrics, isFalse);
      expect(updated.playCount, 3);
      expect(updated.duration, const Duration(seconds: 5));
      expect(updated.mtime, 2000.0);
      expect(updated.createdEpochSec, 1900.0);
      expect(updated.songDateEpochSec, 1800.0);
    });

    test('hasLyrics can be turned off', () {
      // `false` must not read as "not supplied" — clearing lyrics from a file
      // has to be able to clear the flag.
      expect(original.copyWith(hasLyrics: false).hasLyrics, isFalse);
    });

    test('a cover is removed through clearCoverUrl, not a null argument', () {
      expect(original.copyWith(coverUrl: null).coverUrl, original.coverUrl);
      expect(original.copyWith(clearCoverUrl: true).coverUrl, isNull);
    });
  });
}

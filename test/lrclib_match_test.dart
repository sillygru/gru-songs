import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/lrclib_result.dart';
import 'package:wispie/domain/services/lrclib_match.dart';
import 'package:wispie/models/song.dart';

/// LRCLIB search returns up to twenty records for a single track — live cuts,
/// compilations, karaoke uploads and mislabelled rips all mixed together. These
/// tests pin the order the picker shows them in.
void main() {
  const local = Song(
    title: 'Bohemian Rhapsody',
    artist: 'Queen',
    album: 'A Night at the Opera',
    filename: 'bohemian.mp3',
    url: '/music/bohemian.mp3',
    duration: Duration(seconds: 355),
  );

  LrclibResult result({
    required int id,
    String track = 'Bohemian Rhapsody',
    String artist = 'Queen',
    String album = 'A Night at the Opera',
    int? seconds = 355,
    bool synced = true,
    bool plain = true,
    bool instrumental = false,
  }) {
    return LrclibResult(
      id: id,
      trackName: track,
      artistName: artist,
      albumName: album,
      duration: seconds == null ? null : Duration(seconds: seconds),
      instrumental: instrumental,
      plainLyrics: plain ? 'words' : null,
      syncedLyrics: synced ? '[00:00.00] words' : null,
    );
  }

  group('rankLrclibResults', () {
    test('drops records that cannot supply anything', () {
      final ranked = rankLrclibResults([
        result(id: 1, synced: false, plain: false),
        result(id: 2),
      ], local);

      expect(ranked.map((r) => r.id), [2]);
    });

    test('a matching duration beats a distant one', () {
      final ranked = rankLrclibResults([
        result(id: 1, seconds: 240),
        result(id: 2, seconds: 355),
      ], local);

      expect(ranked.first.id, 2);
    });

    test('a two-second drift still counts as an exact match', () {
      final close = scoreLrclibResult(result(id: 1, seconds: 353), local);
      final exact = scoreLrclibResult(result(id: 2, seconds: 355), local);

      expect(close, exact);
    });

    test('duration score falls off between the two thresholds', () {
      final near = scoreLrclibResult(result(id: 1, seconds: 360), local);
      final far = scoreLrclibResult(result(id: 2, seconds: 366), local);
      final beyond = scoreLrclibResult(result(id: 3, seconds: 400), local);

      expect(near, greaterThan(far));
      expect(far, greaterThan(beyond));
    });

    test('a wildly wrong duration is demoted but never discarded', () {
      final ranked = rankLrclibResults([
        result(id: 1, seconds: 30),
      ], local);

      // The only lyrics available must still be reachable — a local file with a
      // bad duration tag should not hide them entirely.
      expect(ranked.map((r) => r.id), [1]);
    });

    test('synced edges out an otherwise identical plain record', () {
      final ranked = rankLrclibResults([
        result(id: 1, synced: false),
        result(id: 2, synced: true),
      ], local);

      expect(ranked.first.id, 2);
    });

    test('an exact title and artist outrank a partial match', () {
      final ranked = rankLrclibResults([
        result(id: 1, track: 'Bohemian Rhapsody (Live)', artist: 'Queen Live'),
        result(id: 2),
      ], local);

      expect(ranked.first.id, 2);
    });

    test('matching ignores case and punctuation', () {
      final punctuated = scoreLrclibResult(
        result(id: 1, track: "Bohemian Rhapsody!", artist: 'QUEEN'),
        local,
      );
      final plainMatch = scoreLrclibResult(result(id: 2), local);

      expect(punctuated, plainMatch);
    });

    test('an instrumental never outranks a real lyric sheet', () {
      final ranked = rankLrclibResults([
        result(id: 1, instrumental: true, synced: false, plain: false),
        result(id: 2),
      ], local);

      expect(ranked.first.id, 2);
      // But it is still offered — it may well be the correct answer.
      expect(ranked.map((r) => r.id), containsAll([1, 2]));
    });

    test('the album breaks a tie between two otherwise equal records', () {
      final ranked = rankLrclibResults([
        result(id: 1, album: 'Greatest Hits'),
        result(id: 2, album: 'A Night at the Opera'),
      ], local);

      expect(ranked.first.id, 2);
    });

    test('equal scores keep their incoming order', () {
      // The service puts the /api/get hit first; ties must not reshuffle it.
      final ranked = rankLrclibResults([
        result(id: 1),
        result(id: 2),
        result(id: 3),
      ], local);

      expect(ranked.map((r) => r.id), [1, 2, 3]);
    });

    test('a local file with no duration falls back to text matching', () {
      const untimed = Song(
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        filename: 'bohemian.mp3',
        url: '/music/bohemian.mp3',
      );

      final ranked = rankLrclibResults([
        result(id: 1, track: 'Something Else', artist: 'Nobody'),
        result(id: 2, seconds: 30),
      ], untimed);

      expect(ranked.first.id, 2);
    });

    test('an empty input yields an empty list', () {
      expect(rankLrclibResults(const [], local), isEmpty);
    });
  });
}

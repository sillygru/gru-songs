import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/lrclib_result.dart';

/// Parsing tests for the LRCLIB payload. Deliberately offline: the fixtures
/// below are real responses captured from lrclib.net, so the shape is pinned
/// without the suite ever making a network request.
void main() {
  group('LrclibResult.fromJson', () {
    test('reads a full synced record, converting seconds to a Duration', () {
      final result = LrclibResult.fromJson(jsonDecode('''
        {
          "id": 19080,
          "name": "Bohemian Rhapsody",
          "trackName": "Bohemian Rhapsody",
          "artistName": "Queen",
          "albumName": "A Night at the Opera",
          "duration": 355.0,
          "instrumental": false,
          "plainLyrics": "Is this the real life?",
          "syncedLyrics": "[00:00.00] Is this the real life?"
        }
      '''));

      expect(result.id, 19080);
      expect(result.trackName, 'Bohemian Rhapsody');
      expect(result.artistName, 'Queen');
      expect(result.albumName, 'A Night at the Opera');
      // The API reports seconds, not milliseconds.
      expect(result.duration, const Duration(seconds: 355));
      expect(result.instrumental, isFalse);
      expect(result.hasSynced, isTrue);
      expect(result.hasPlain, isTrue);
    });

    test('keeps fractional seconds', () {
      final result = LrclibResult.fromJson(const {
        'id': 1,
        'trackName': 'A',
        'artistName': 'B',
        'albumName': 'C',
        'duration': 353.5,
      });

      expect(result.duration, const Duration(milliseconds: 353500));
    });

    test('treats a null or blank lyric field as absent', () {
      final result = LrclibResult.fromJson(const {
        'id': 2,
        'trackName': 'A',
        'artistName': 'B',
        'albumName': 'C',
        'duration': 100,
        'plainLyrics': 'words',
        'syncedLyrics': null,
      });

      expect(result.hasSynced, isFalse);
      expect(result.hasPlain, isTrue);
      expect(result.isUsable, isTrue);

      final blank = LrclibResult.fromJson(const {
        'id': 3,
        'trackName': 'A',
        'artistName': 'B',
        'albumName': 'C',
        'plainLyrics': '   ',
      });
      expect(blank.hasPlain, isFalse);
      expect(blank.isUsable, isFalse);
    });

    test('an instrumental is usable even with no lyrics at all', () {
      final result = LrclibResult.fromJson(const {
        'id': 4,
        'trackName': 'Interlude',
        'artistName': 'B',
        'albumName': 'C',
        'duration': 42,
        'instrumental': true,
        'plainLyrics': null,
        'syncedLyrics': null,
      });

      expect(result.instrumental, isTrue);
      expect(result.isUsable, isTrue);
      // Applying it clears the file's lyrics rather than writing words.
      expect(result.lyricsFor(), '');
      expect(result.lyricsFor(preferPlain: true), '');
    });

    test('falls back to name when trackName is missing, and survives gaps', () {
      final result = LrclibResult.fromJson(const {
        'id': 5,
        'name': 'Fallback Title',
      });

      expect(result.trackName, 'Fallback Title');
      expect(result.artistName, '');
      expect(result.albumName, '');
      expect(result.duration, isNull);
      expect(result.isUsable, isFalse);
    });

    test('a zero duration means unknown, not an instant-long track', () {
      final result = LrclibResult.fromJson(const {
        'id': 6,
        'trackName': 'A',
        'duration': 0,
      });

      expect(result.duration, isNull);
    });
  });

  group('lyricsFor', () {
    const both = LrclibResult(
      id: 7,
      trackName: 'A',
      artistName: 'B',
      albumName: 'C',
      plainLyrics: 'plain',
      syncedLyrics: '[00:01.00] synced',
    );

    test('prefers synced by default', () {
      expect(both.lyricsFor(), '[00:01.00] synced');
    });

    test('honours a plain preference', () {
      expect(both.lyricsFor(preferPlain: true), 'plain');
    });

    test('falls back to whichever it has when the preferred one is missing',
        () {
      const syncedOnly = LrclibResult(
        id: 8,
        trackName: 'A',
        artistName: 'B',
        albumName: 'C',
        syncedLyrics: '[00:01.00] synced',
      );

      expect(syncedOnly.lyricsFor(preferPlain: true), '[00:01.00] synced');
    });

    test('returns null when there is nothing to apply', () {
      const empty = LrclibResult(
        id: 9,
        trackName: 'A',
        artistName: 'B',
        albumName: 'C',
      );

      expect(empty.lyricsFor(), isNull);
    });
  });

  test('the TrackNotFound body is not mistaken for a result', () {
    // What /api/get returns on a miss. The service checks the status code, but
    // the body must not parse into something that looks usable either.
    final decoded = jsonDecode(
      '{"message":"Failed to find specified track",'
      '"name":"TrackNotFound","statusCode":404}',
    ) as Map<String, dynamic>;

    final result = LrclibResult.fromJson(decoded);
    expect(result.id, 0);
    expect(result.isUsable, isFalse);
  });
}

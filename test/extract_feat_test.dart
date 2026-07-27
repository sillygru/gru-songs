import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/providers/providers.dart';

void main() {
  group('extractFeatFromSong', () {
    Song song({
      required String title,
      String artist = 'Test Artist',
      String album = 'Test Album',
      String filename = 'test.mp3',
      String url = '/music/test.mp3',
    }) {
      return Song(
        title: title,
        artist: artist,
        album: album,
        filename: filename,
        url: url,
      );
    }

    group('standard feat patterns', () {
      test('extracts feat artist from parenthesised title', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (feat. John Doe)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, John Doe');
      });

      test('extracts feat artist from bracketed title', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title [feat. John Doe]'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, John Doe');
      });

      test('extracts ft. (abbreviated) artist', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (ft. Jane Smith)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, Jane Smith');
      });

      test('extracts featuring artist', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (featuring Bob Jones)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, Bob Jones');
      });

      test('extracts feat artist without brackets', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title feat. John Doe'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, John Doe');
      });

      test('extracts ft. without brackets nor dot', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title ft John Doe'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, John Doe');
      });

      test('extracts with case insensitive matching', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (FEAT. JOHN DOE)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, JOHN DOE');
      });
    });

    group('artist field handling', () {
      test('sets feat artist as sole artist when original is Unknown Artist',
          () {
        final result = extractFeatFromSong(
          song(
            title: 'Song Title (feat. John Doe)',
            artist: 'Unknown Artist',
          ),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'John Doe');
      });

      test('appends feat artist to existing multi-artist field', () {
        final result = extractFeatFromSong(
          song(
            title: 'Song Title (feat. John Doe)',
            artist: 'Main Artist',
          ),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Main Artist, John Doe');
      });
    });

    group('edge cases - should extract correctly', () {
      test('handles ampersand in feat artist name', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (feat. Artist 1 & Artist 2)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, Artist 1 & Artist 2');
      });

      test('handles comma in feat artist name', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (feat. Artist 1, Artist 2, and Artist 3)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, Artist 1, Artist 2, and Artist 3');
      });

      test('handles single-letter feat artist name', () {
        final result = extractFeatFromSong(
          song(title: 'Song Title (feat. X)'),
        );
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, X');
      });
    });

    group('edge cases - should NOT extract (return song unchanged)', () {
      test('does not extract when extra content follows closing bracket', () {
        final input = song(title: 'Song Title (feat. Artist) (Remix)');
        final result = extractFeatFromSong(input);
        expect(result, same(input));
      });

      test('does not extract when extra content in brackets follows', () {
        final input = song(title: 'Song Title (feat. Artist) [Official]');
        final result = extractFeatFromSong(input);
        expect(result, same(input));
      });

      test('extracts the last feat marker when multiple present', () {
        // The $ anchor ensures only the end-of-string feat marker matches,
        // leaving earlier feat content in the title.
        final result = extractFeatFromSong(
          song(title: 'Song Title (feat. Artist 1) (feat. Artist 2)'),
        );
        expect(result.title, 'Song Title (feat. Artist 1)');
        expect(result.artist, 'Test Artist, Artist 2');
      });

      test('does not extract when title has no feat marker', () {
        final input = song(title: 'Song Title');
        final result = extractFeatFromSong(input);
        expect(result, same(input));
      });

      test('does not extract empty feat artist', () {
        final input = song(title: 'Song Title (feat. )');
        final result = extractFeatFromSong(input);
        expect(result, same(input));
      });

      test('preserves other song fields unchanged on match', () {
        final input = song(
          title: 'Song Title (feat. John Doe)',
          artist: 'Test Artist',
          album: 'Test Album',
          filename: 'test.mp3',
          url: '/music/test.mp3',
        );
        final result = extractFeatFromSong(input);
        expect(result.title, 'Song Title');
        expect(result.artist, 'Test Artist, John Doe');
        expect(result.album, input.album);
        expect(result.filename, input.filename);
        expect(result.url, input.url);
        expect(result.coverUrl, input.coverUrl);
        expect(result.hasLyrics, input.hasLyrics);
        expect(result.duration, input.duration);
      });
    });
  });
}

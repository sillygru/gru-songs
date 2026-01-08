import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';

void main() {
  group('Song Model', () {
    test('Song.fromJson should create a valid Song object', () {
      final json = {
        'title': 'Test Song',
        'artist': 'Test Artist',
        'album': 'Test Album',
        'filename': 'test.mp3',
        'url': '/stream/test.mp3',
        'lyrics_url': '/lyrics/test.lrc',
        'cover_url': '/cover/test.mp3'
      };

      final song = Song.fromJson(json);

      expect(song.title, 'Test Song');
      expect(song.artist, 'Test Artist');
      expect(song.album, 'Test Album');
      expect(song.filename, 'test.mp3');
      expect(song.url, '/stream/test.mp3');
      expect(song.lyricsUrl, '/lyrics/test.lrc');
      expect(song.coverUrl, '/cover/test.mp3');
    });

    test('Song.fromJson should handle missing fields with defaults', () {
      final json = {
        'filename': 'test.mp3',
        'url': '/stream/test.mp3',
      };

      final song = Song.fromJson(json);

      expect(song.title, 'Unknown Title');
      expect(song.artist, 'Unknown Artist');
      expect(song.album, 'Unknown Album');
    });
  });

  group('LyricLine Parsing', () {
    test('LyricLine.parse should correctly parse timed lyrics', () {
      const content = '[00:12.34]Hello world\n[01:02.00]Second line';
      final lyrics = LyricLine.parse(content);

      expect(lyrics.length, 2);
      expect(lyrics[0].time.inMilliseconds, 12340);
      expect(lyrics[0].text, 'Hello world');
      expect(lyrics[1].time.inMinutes, 1);
      expect(lyrics[1].time.inSeconds, 62);
      expect(lyrics[1].text, 'Second line');
    });

    test('LyricLine.parse should handle non-timed lyrics', () {
      const content = 'Just some text\nMore text';
      final lyrics = LyricLine.parse(content);

      expect(lyrics.length, 2);
      expect(lyrics[0].time, Duration.zero);
      expect(lyrics[0].text, 'Just some text');
    });
  });
}

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
        'has_lyrics': true,
        'cover_url': '/cover/test.mp3'
      };

      final song = Song.fromJson(json);

      expect(song.title, 'Test Song');
      expect(song.artist, 'Test Artist');
      expect(song.album, 'Test Album');
      expect(song.filename, 'test.mp3');
      expect(song.url, '/stream/test.mp3');
      expect(song.hasLyrics, true);
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
}

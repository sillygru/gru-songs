import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';

void main() {
  group('Serialization Tests', () {
    test('Song serialization round-trip', () {
      const song = Song(
        title: 'Test Title',
        artist: 'Test Artist',
        album: 'Test Album',
        filename: 'test.mp3',
        url: 'http://test.com/test.mp3',
        lyricsUrl: 'http://test.com/lyrics',
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
      final item = QueueItem(song: song, isPriority: true);

      final json = item.toJson();
      final fromJson = QueueItem.fromJson(json);

      expect(fromJson.song.filename, item.song.filename);
      expect(fromJson.queueId, item.queueId);
      expect(fromJson.isPriority, item.isPriority);
    });
  });
}

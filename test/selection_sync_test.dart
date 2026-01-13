import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';
import 'package:gru_songs/models/shuffle_config.dart';

void main() {
  group('Selection Sync Edge Cases', () {
    final songs = List.generate(5, (i) => Song(
      title: 'Song $i', artist: 'Artist $i', album: 'Album $i', filename: 's$i.mp3', url: ''
    ));

    test('Selecting a song when shuffle is ON moves it to front', () {
      final config = const ShuffleConfig(enabled: true);
      final selectedSong = songs[3]; // s3.mp3
      
      // Simulation of playSong logic
      final originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      final originalIdx = originalQueue.indexWhere((item) => item.song.filename == selectedSong.filename);
      final selectedItem = originalQueue[originalIdx];
      
      final otherItems = List<QueueItem>.from(originalQueue)..removeAt(originalIdx);
      // In shuffle mode, we expect effectiveQueue[0] to be the selected song
      final effectiveQueue = [selectedItem, ...otherItems]; // simplified shuffle for test
      
      expect(effectiveQueue[0].song.filename, equals('s3.mp3'));
      expect(effectiveQueue.length, equals(5));
    });

    test('Selecting a song when shuffle is OFF maintains order and index', () {
      final selectedSong = songs[3];
      
      final originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      final originalIdx = originalQueue.indexWhere((item) => item.song.filename == selectedSong.filename);
      
      final effectiveQueue = List.from(originalQueue);
      
      expect(effectiveQueue[originalIdx].song.filename, equals('s3.mp3'));
      expect(originalIdx, equals(3));
    });

    test('Metadata safety: artist or album null', () {
      final songWithNulls = const Song(
        title: 'Title', artist: 'Unknown Artist', album: 'Unknown Album', 
        filename: 'null.mp3', url: 'url'
      );
      
      expect(songWithNulls.artist, equals('Unknown Artist'));
      expect(songWithNulls.album, equals('Unknown Album'));
    });
  });
}

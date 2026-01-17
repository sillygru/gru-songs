import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';

void main() {
  group('QueueItem', () {
    final song = Song(
      title: 'Test',
      artist: 'Artist',
      album: 'Album',
      filename: 'test.mp3',
      url: 'url',
    );

    test('QueueItem should have unique IDs', () {
      final item1 = QueueItem(song: song);
      final item2 = QueueItem(song: song);
      expect(item1.queueId, isNot(item2.queueId));
    });

    test('QueueItem equality should respect queueId', () {
      final item1 = QueueItem(song: song, queueId: '1');
      final item2 = QueueItem(song: song, queueId: '1');
      final item3 = QueueItem(song: song, queueId: '2');

      expect(item1, item2);
      expect(item1, isNot(item3));
    });
  });

  group('Priority Block Logic Simulation', () {
    // This simulates the logic inside AudioPlayerManager
    test('Shuffle should keep priority items after current', () {
      final songs = List.generate(
          5,
          (i) => Song(
                title: 'Song $i',
                artist: 'Artist',
                album: 'Album',
                filename: 'song$i.mp3',
                url: 'url$i',
              ));

      List<QueueItem> effectiveQueue =
          songs.map((s) => QueueItem(song: s)).toList();

      // Current song is at index 0 (Song 0)
      final currentItem = effectiveQueue[0];

      // Add a priority song at index 1
      final prioritySong = Song(
          title: 'Priority',
          artist: 'A',
          album: 'A',
          filename: 'p.mp3',
          url: 'u');
      final priorityItem = QueueItem(song: prioritySong, isPriority: true);
      effectiveQueue.insert(1, priorityItem);

      // Queue is now [Song 0, Priority, Song 1, Song 2, Song 3, Song 4]
      expect(effectiveQueue[1].song.title, 'Priority');

      // Simulate shuffle
      final otherItems =
          effectiveQueue.where((item) => item != currentItem).toList();
      final priorityItems =
          otherItems.where((item) => item.isPriority).toList();
      final normalItems = otherItems.where((item) => !item.isPriority).toList();

      normalItems.shuffle();

      final shuffledQueue = [
        currentItem,
        ...priorityItems,
        ...normalItems,
      ];

      expect(shuffledQueue[0], currentItem);
      expect(shuffledQueue[1], priorityItem);
      expect(shuffledQueue.length, 6);
      expect(shuffledQueue.contains(priorityItem), true);
    });
  });
}

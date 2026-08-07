import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';

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
}

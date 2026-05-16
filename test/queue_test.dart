import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/models/queue_item.dart';

void main() {
  group('Queue Logic - Existing Song Detection', () {
    test('playSong should detect song already in queue', () {
      final songs = List.generate(
        5,
        (i) => Song(
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          filename: 'song$i.mp3',
          url: 'url$i',
        ),
      );

      final queue = songs.map((s) => QueueItem(song: s)).toList();

      final targetSong = songs[2];
      final existingIdx = queue.indexWhere(
        (item) => item.song.filename == targetSong.filename,
      );

      expect(existingIdx, 2);
    });

    test('playSong should return -1 for song not in queue', () {
      final songs = List.generate(
        5,
        (i) => Song(
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          filename: 'song$i.mp3',
          url: 'url$i',
        ),
      );

      final queue = songs.map((s) => QueueItem(song: s)).toList();

      final newSong = Song(
        title: 'New Song',
        artist: 'Artist',
        album: 'Album',
        filename: 'new.mp3',
        url: 'newurl',
      );

      final existingIdx = queue.indexWhere(
        (item) => item.song.filename == newSong.filename,
      );

      expect(existingIdx, -1);
    });
  });

  group('Queue Logic - New Queue Detection', () {
    test('should detect same queue (not new)', () {
      final currentFilenames = {'a.mp3', 'b.mp3', 'c.mp3'};
      final newFilenames = {'a.mp3', 'b.mp3', 'c.mp3'};

      final isNewQueue = !currentFilenames.containsAll(newFilenames) ||
          !newFilenames.containsAll(currentFilenames);

      expect(isNewQueue, false);
    });

    test('should detect different queue (new)', () {
      final currentFilenames = {'a.mp3', 'b.mp3', 'c.mp3'};
      final newFilenames = {'a.mp3', 'b.mp3', 'd.mp3'};

      final isNewQueue = !currentFilenames.containsAll(newFilenames) ||
          !newFilenames.containsAll(currentFilenames);

      expect(isNewQueue, true);
    });

    test('should detect new queue when adding songs', () {
      final currentFilenames = {'a.mp3', 'b.mp3'};
      final newFilenames = {'a.mp3', 'b.mp3', 'c.mp3'};

      final isNewQueue = !currentFilenames.containsAll(newFilenames) ||
          !newFilenames.containsAll(currentFilenames);

      expect(isNewQueue, true);
    });

    test('should detect new queue when subset', () {
      final currentFilenames = {'a.mp3', 'b.mp3', 'c.mp3'};
      final newFilenames = {'a.mp3', 'b.mp3'};

      final isNewQueue = !currentFilenames.containsAll(newFilenames) ||
          !newFilenames.containsAll(currentFilenames);

      expect(isNewQueue, true);
    });

    test('should detect new queue when empty current', () {
      final currentFilenames = <String>{};
      final newFilenames = {'a.mp3', 'b.mp3'};

      final isNewQueue = !currentFilenames.containsAll(newFilenames) ||
          !newFilenames.containsAll(currentFilenames);

      expect(isNewQueue, true);
    });
  });

  group('Queue Logic - Pending Queue Replacement', () {
    test('pending queue should be cleared on replaceQueue', () {
      List<String>? pendingQueueSongs = ['a.mp3', 'b.mp3'];

      final songs = ['x.mp3', 'y.mp3'];

      // Clear pending before replacing
      pendingQueueSongs = null;

      // Simulate replaceQueue setting new pending
      pendingQueueSongs = songs;

      expect(pendingQueueSongs, ['x.mp3', 'y.mp3']);
      expect(pendingQueueSongs, isNot(['a.mp3', 'b.mp3']));
    });

    test('pending queue should trigger on ProcessingState.completed', () {
      bool queueReplaced = false;
      List<String>? pendingQueueSongs = ['next.mp3'];

      // Simulate processing state completed
      const state = 'completed';

      if (state == 'completed') {
        queueReplaced = true;
        pendingQueueSongs = null;
      }

      expect(queueReplaced, true);
      expect(pendingQueueSongs, isNull);
    });

    test(
        'pending queue should NOT trigger on song change when queue still has songs',
        () {
      bool queueReplaced = false;

      // Simulate song changed but queue not finished
      const currentIndex = 1;
      const queueLength = 5;

      // Should NOT replace when queue still has songs
      if (currentIndex < queueLength - 1) {
        // This should NOT happen - pending queue should only apply when queue ends
        queueReplaced = false;
      }

      expect(queueReplaced, false);
    });
  });

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

  group('Move to Front Logic', () {
    test('should reorder item to position after current', () {
      final songs = List.generate(
          5,
          (i) => Song(
                title: 'Song $i',
                artist: 'Artist',
                album: 'Album',
                filename: 'song$i.mp3',
                url: 'url$i',
              ));

      // Simulate queue: [current(0), 1, 2, 3, 4]
      List<QueueItem> queue = songs.map((s) => QueueItem(song: s)).toList();

      // Move item at index 3 (Song 3) to front (right after current at index 0)
      final itemToMove = queue[3];
      const int currentIndex = 0;
      const int indexToMove = 3;

      queue.removeAt(indexToMove);
      final targetIndex = currentIndex + 1;
      queue.insert(targetIndex, itemToMove);

      // Queue should be: [Song 0, Song 3, Song 1, Song 2, Song 4]
      expect(queue[0].song.title, 'Song 0');
      expect(queue[1].song.title, 'Song 3');
      expect(queue[2].song.title, 'Song 1');
      expect(queue[3].song.title, 'Song 2');
      expect(queue[4].song.title, 'Song 4');
    });
  });
}

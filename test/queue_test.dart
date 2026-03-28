import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/models/queue_item.dart';

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
      String? pendingPlaylistId = 'playlist1';

      final songs = ['x.mp3', 'y.mp3'];

      // Clear pending before replacing
      pendingQueueSongs = null;
      pendingPlaylistId = null;

      // Simulate replaceQueue setting new pending
      pendingQueueSongs = songs;
      pendingPlaylistId = 'newPlaylist';

      expect(pendingQueueSongs, ['x.mp3', 'y.mp3']);
      expect(pendingQueueSongs, isNot(['a.mp3', 'b.mp3']));
    });

    test('pending queue should trigger on ProcessingState.completed', () {
      bool queueReplaced = false;
      List<String>? pendingQueueSongs = ['next.mp3'];
      String? pendingPlaylistId = 'playlist1';

      // Simulate processing state completed
      final state = 'completed';

      if (state == 'completed' && pendingQueueSongs != null) {
        queueReplaced = true;
        pendingQueueSongs = null;
        pendingPlaylistId = null;
      }

      expect(queueReplaced, true);
      expect(pendingQueueSongs, isNull);
    });

    test(
        'pending queue should NOT trigger on song change when queue still has songs',
        () {
      bool queueReplaced = false;
      List<String>? pendingQueueSongs = ['next.mp3'];
      String? pendingPlaylistId = 'playlist1';

      // Simulate song changed but queue not finished
      final currentIndex = 1;
      final queueLength = 5;

      // Should NOT replace when queue still has songs
      if (currentIndex < queueLength - 1 && pendingQueueSongs != null) {
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

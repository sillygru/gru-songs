import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/services/library_logic.dart';

void main() {
  group('LibraryLogic', () {
    test('sorts by date added using stored timestamp first', () {
      final songs = [
        const Song(
          title: 'Older',
          artist: 'Artist',
          album: 'Album',
          filename: 'older.mp3',
          url: '/music/older.mp3',
          createdEpochSec: 1000,
        ),
        const Song(
          title: 'Newer',
          artist: 'Artist',
          album: 'Album',
          filename: 'newer.mp3',
          url: '/music/newer.mp3',
          createdEpochSec: 2000,
        ),
      ];

      final sorted = LibraryLogic.sortSongs(songs, SongSortOrder.dateAdded);
      expect(sorted.first.filename, 'newer.mp3');
      expect(sorted.last.filename, 'older.mp3');
    });
  });
}

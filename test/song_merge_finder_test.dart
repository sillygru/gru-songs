import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/song_merge_finder.dart';
import 'package:wispie/models/song.dart';

void main() {
  group('SongMergeFinder', () {
    test('detects title variants by same artist', () {
      final songs = [
        Song(
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          album: 'After Hours',
          filename: 'song1.mp3',
          url: '/path/song1.mp3',
        ),
        Song(
          title: 'Blinding Lights (Remix)',
          artist: 'The Weeknd',
          album: 'After Hours',
          filename: 'song2.mp3',
          url: '/path/song2.mp3',
        ),
        Song(
          title: 'Starboy',
          artist: 'The Weeknd',
          album: 'Starboy',
          filename: 'song3.mp3',
          url: '/path/song3.mp3',
        ),
      ];

      final candidates = SongMergeFinder.findCandidates(songs, {});
      expect(candidates.length, 1);
      expect(candidates.first.songs.length, 2);
      expect(candidates.first.songs.map((s) => s.filename),
          containsAll(['song1.mp3', 'song2.mp3']));
    });

    test('ignores songs already merged together', () {
      final songs = [
        Song(
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          album: 'After Hours',
          filename: 'song1.mp3',
          url: '/path/song1.mp3',
        ),
        Song(
          title: 'Blinding Lights (Remix)',
          artist: 'The Weeknd',
          album: 'After Hours',
          filename: 'song2.mp3',
          url: '/path/song2.mp3',
        ),
      ];

      final existingGroups = {
        'group1': ['song1.mp3', 'song2.mp3'],
      };

      final candidates = SongMergeFinder.findCandidates(songs, existingGroups);
      expect(candidates.isEmpty, true);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/services/bulk_metadata_service.dart';
import 'package:gru_songs/providers/selection_provider.dart';

void main() {
  group('SelectionState Tests', () {
    test('initial state is empty', () {
      final state = SelectionState();
      expect(state.isSelectionMode, false);
      expect(state.selectedFilenames, isEmpty);
    });

    test('copyWith updates values correctly', () {
      final state = SelectionState();
      final updated = state.copyWith(
        isSelectionMode: true,
        selectedFilenames: {'song1.mp3'},
      );
      expect(updated.isSelectionMode, true);
      expect(updated.selectedFilenames, {'song1.mp3'});
    });
  });

  group('BulkMetadataPlan Tests', () {
    final song1 = Song(
      title: 'Song One',
      artist: 'Artist A',
      album: 'Album X',
      filename: 'song1.mp3',
      url: '/path/song1.mp3',
      playCount: 0,
      mtime: 0,
    );

    final song2 = Song(
      title: 'Song Two',
      artist: 'Artist B',
      album: 'Album Y',
      filename: 'song2.mp3',
      url: '/path/song2.mp3',
      playCount: 0,
      mtime: 0,
    );

    test('ArtistBulkMode.set updates artist', () {
      final plan = BulkMetadataPlan(
        artistMode: ArtistBulkMode.set,
        artistValue: 'New Artist',
      );

      final updated = plan.apply(song1);
      expect(updated.artist, 'New Artist');
      expect(updated.title, song1.title);
    });

    test('ArtistBulkMode.append updates artist with joiner', () {
      final plan = BulkMetadataPlan(
        artistMode: ArtistBulkMode.append,
        artistValue: 'Feature',
        artistJoiner: ' & ',
      );

      final updated = plan.apply(song1);
      expect(updated.artist, 'Artist A & Feature');
    });

    test('Title replacement works case-insensitively', () {
      final plan = BulkMetadataPlan(
        titleMode: TitleBulkMode.replace,
        titleFind: 'one',
        titleReplace: '1',
        titleCaseSensitive: false,
      );

      final updated = plan.apply(song1);
      expect(updated.title, 'Song 1');
    });

    test('Album set updates album for all songs', () {
      final plan = BulkMetadataPlan(albumValue: 'Common Album');

      expect(plan.apply(song1).album, 'Common Album');
      expect(plan.apply(song2).album, 'Common Album');
    });

    test('countChanges correctly counts songs that will be modified', () {
      final plan = BulkMetadataPlan(
          artistMode: ArtistBulkMode.set, artistValue: 'Artist A');
      // song1 already has 'Artist A', song2 does not.
      final songs = [song1, song2];

      expect(plan.countChanges(songs), 1);
    });

    test('buildPreview returns modified items up to limit', () {
      final plan = BulkMetadataPlan(albumValue: 'New');
      final songs = [song1, song2];

      final preview = plan.buildPreview(songs, limit: 1);
      expect(preview.length, 1);
      expect(preview.first.original.filename, song1.filename);
      expect(preview.first.updated.album, 'New');
    });

    test('isEmpty returns true when no changes defined', () {
      final plan = BulkMetadataPlan();
      expect(plan.isEmpty, true);
    });
  });
}

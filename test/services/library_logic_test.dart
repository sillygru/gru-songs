import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  group('LibraryLogic.resolveLibraryRoot', () {
    Song songAt(String url) => Song(
          title: p.basenameWithoutExtension(url),
          artist: 'Artist',
          album: 'Album',
          filename: p.basename(url),
          url: url,
        );

    test('uses the configured folder that holds the songs', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: [songAt('/storage/Music/a.mp3')],
        configuredFolders: const ['/storage/Music'],
      );

      expect(root, '/storage/Music');
    });

    test('normalizes trailing separators on the configured folder', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: [songAt('/storage/Music/a.mp3')],
        configuredFolders: const ['/storage/Music/'],
      );

      expect(root, '/storage/Music');
    });

    test('spans every configured folder that holds songs', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: [
          songAt('/storage/Music/a.mp3'),
          songAt('/storage/Downloads/b.mp3'),
        ],
        configuredFolders: const ['/storage/Music', '/storage/Downloads'],
      );

      // Both folders stay reachable in the tree instead of only the first one.
      expect(root, '/storage');
    });

    test('ignores configured folders that hold no songs', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: [songAt('/storage/Music/a.mp3')],
        configuredFolders: const ['/storage/Empty', '/storage/Music'],
      );

      expect(root, '/storage/Music');
    });

    test('falls back to the songs when no configured folder matches', () {
      // Paths drifted (iOS container id changed, SD card remounted): the
      // library must still list everything instead of looking empty.
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: [
          songAt('/var/mobile/NEW/Music/a.mp3'),
          songAt('/var/mobile/NEW/Music/Rock/b.mp3'),
        ],
        configuredFolders: const ['/var/mobile/OLD/Music'],
      );

      expect(root, '/var/mobile/NEW/Music');
    });

    test('keeps the configured folder when the library is empty', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: const [],
        configuredFolders: const ['/storage/Music'],
      );

      expect(root, '/storage/Music');
    });

    test('returns null when there is no folder and no song', () {
      final root = LibraryLogic.resolveLibraryRoot(
        allSongs: const [],
        configuredFolders: const ['', '  '],
      );

      expect(root, isNull);
    });
  });

  group('LibraryLogic.getFolderContent', () {
    test('matches songs against a non-normalized root', () {
      final content = LibraryLogic.getFolderContent(
        allSongs: [
          const Song(
            title: 'A',
            artist: 'Artist',
            album: 'Album',
            filename: 'a.mp3',
            url: '/storage/Music/a.mp3',
          ),
          const Song(
            title: 'B',
            artist: 'Artist',
            album: 'Album',
            filename: 'b.mp3',
            url: '/storage/Music/Rock/b.mp3',
          ),
        ],
        currentFullPath: '/storage/Music/',
      );

      expect(content.allSongsInFolder, hasLength(2));
      expect(content.immediateSongs.single.filename, 'a.mp3');
      expect(content.subFolders, ['Rock']);
    });
  });
}

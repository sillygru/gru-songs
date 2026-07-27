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

  group('LibraryLogic.splitArtistNames', () {
    test('splits artists by ampersand, comma, feat, ft, and, slash', () {
      expect(LibraryLogic.splitArtistNames('Drake & 21 Savage'),
          ['Drake', '21 Savage']);
      expect(LibraryLogic.splitArtistNames('Kanye West ft. Rihanna'),
          ['Kanye West', 'Rihanna']);
      expect(LibraryLogic.splitArtistNames('Lady Gaga, Bruno Mars'),
          ['Lady Gaga', 'Bruno Mars']);
      expect(LibraryLogic.splitArtistNames('Artist 1 and Artist 2'),
          ['Artist 1', 'Artist 2']);
      expect(LibraryLogic.splitArtistNames('Artist 1 / Artist 2'),
          ['Artist 1', 'Artist 2']);
    });
  });

  group('LibraryLogic.groupByArtist', () {
    test('puts multi-artist songs under each individual artist card', () {
      final songs = [
        const Song(
          title: 'Collaboration',
          artist: 'Artist A & Artist B',
          album: 'Album 1',
          filename: 'collab.mp3',
          url: '/music/collab.mp3',
        ),
        const Song(
          title: 'Solo A',
          artist: 'Artist A',
          album: 'Album 1',
          filename: 'solo_a.mp3',
          url: '/music/solo_a.mp3',
        ),
      ];

      final grouped = LibraryLogic.groupByArtist(songs);

      expect(grouped.keys, containsAll(['Artist A', 'Artist B']));
      expect(grouped['Artist A']!.map((s) => s.filename),
          containsAll(['collab.mp3', 'solo_a.mp3']));
      expect(grouped['Artist B']!.map((s) => s.filename), ['collab.mp3']);
    });
  });

  group('LibraryLogic.sortAlbumsByTrackCount', () {
    test('sorts albums by most tracks first', () {
      final albumMap = {
        'Album Single': [
          const Song(
            title: 'Track 1',
            artist: 'Artist',
            album: 'Album Single',
            filename: '1.mp3',
            url: '/1.mp3',
          ),
        ],
        'Album Big': [
          const Song(
            title: 'Track 1',
            artist: 'Artist',
            album: 'Album Big',
            filename: '2.mp3',
            url: '/2.mp3',
          ),
          const Song(
            title: 'Track 2',
            artist: 'Artist',
            album: 'Album Big',
            filename: '3.mp3',
            url: '/3.mp3',
          ),
        ],
      };

      final sorted = LibraryLogic.sortAlbumsByTrackCount(albumMap);

      expect(sorted, ['Album Big', 'Album Single']);
    });
  });

  group('LibraryLogic.sortArtistsByTrackCount', () {
    test('sorts artists by most tracks first', () {
      final artistMap = {
        'Artist Few': [
          const Song(
            title: 'Track 1',
            artist: 'Artist Few',
            album: 'Album',
            filename: '1.mp3',
            url: '/1.mp3',
          ),
        ],
        'Artist Many': [
          const Song(
            title: 'Track 1',
            artist: 'Artist Many',
            album: 'Album',
            filename: '2.mp3',
            url: '/2.mp3',
          ),
          const Song(
            title: 'Track 2',
            artist: 'Artist Many',
            album: 'Album',
            filename: '3.mp3',
            url: '/3.mp3',
          ),
        ],
      };

      final sorted = LibraryLogic.sortArtistsByTrackCount(artistMap);

      expect(sorted, ['Artist Many', 'Artist Few']);
    });
  });
}

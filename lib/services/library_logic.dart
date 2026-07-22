import 'dart:math';
import 'package:path/path.dart' as p;
import '../models/song.dart';
import '../models/shuffle_config.dart';
import '../providers/user_data_provider.dart';

class LibraryFolderContent {
  final List<String> subFolders;
  final List<Song> immediateSongs;
  final List<Song> allSongsInFolder;
  final Map<String, List<Song>> subFolderSongs;

  LibraryFolderContent({
    required this.subFolders,
    required this.immediateSongs,
    required this.allSongsInFolder,
    required this.subFolderSongs,
  });
}

class LibraryLogic {
  /// Picks the folder the "Folders" tab should be rooted at.
  ///
  /// The library tree used to be rooted at the *first* configured music folder,
  /// which made songs disappear from the tab whenever that folder was not the
  /// one holding them — extra folders added later, or a root whose absolute
  /// path drifted (iOS re-resolves its container path on reinstall, Android SAF
  /// can hand back a different mount). Home kept showing those songs because it
  /// never filters by path, so the library looked empty for no visible reason.
  ///
  /// The root is therefore derived from what is actually in the library:
  /// configured folders that hold songs win, several of them collapse to their
  /// common ancestor, and if none of them match the scanned paths we fall back
  /// to the common ancestor of the songs themselves. Only sub-folders that
  /// contain songs are ever listed, so a shallow root adds at most a level of
  /// drill-down — it never exposes unrelated directories.
  ///
  /// Returns `null` only when there is nothing to show at all.
  static String? resolveLibraryRoot({
    required List<Song> allSongs,
    required List<String> configuredFolders,
  }) {
    final roots = <String>[];
    for (final folder in configuredFolders) {
      final normalized = normalizePath(folder);
      if (normalized.isEmpty || roots.contains(normalized)) continue;
      roots.add(normalized);
    }

    final matching = roots
        .where((root) => allSongs.any((song) => isUnder(root, song.url)))
        .toList();

    if (matching.length == 1) return matching.first;
    if (matching.length > 1) return _commonAncestor(matching);

    if (allSongs.isEmpty) return roots.isEmpty ? null : roots.first;

    return _commonAncestor(allSongs.map((song) => p.dirname(song.url)));
  }

  static String normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    return p.normalize(trimmed);
  }

  /// Whether [songUrl] is [root] itself or lives somewhere below it.
  static bool isUnder(String root, String songUrl) {
    if (root.isEmpty || songUrl.isEmpty) return false;
    final normalized = normalizePath(songUrl);
    return normalized == root || p.isWithin(root, normalized);
  }

  /// Deepest directory containing every path in [paths], or `null` if they
  /// share nothing (different drives on Windows, empty input).
  static String? _commonAncestor(Iterable<String> paths) {
    List<String>? common;

    for (final path in paths) {
      final parts = p.split(normalizePath(path));
      if (common == null) {
        common = parts;
        continue;
      }

      final limit = common.length < parts.length ? common.length : parts.length;
      var shared = 0;
      while (shared < limit && common[shared] == parts[shared]) {
        shared++;
      }
      common = common.sublist(0, shared);
      if (common.isEmpty) return null;
    }

    if (common == null || common.isEmpty) return null;
    return p.joinAll(common);
  }

  static List<Song> sortSongs(
    List<Song> songs,
    SongSortOrder sortOrder, {
    UserDataState? userData,
    ShuffleConfig? shuffleConfig,
    Map<String, int>? playCounts,
  }) {
    final sorted = List<Song>.from(songs);

    // Pre-compute lowercase title/artist/album strings once per sort to avoid
    // calling toLowerCase() O(N log N) times during comparator evaluations.
    final lowerTitle = <String, String>{};
    final lowerArtist = <String, String>{};
    final lowerAlbum = <String, String>{};
    for (final s in sorted) {
      lowerTitle[s.filename] = s.title.toLowerCase();
      lowerArtist[s.filename] = s.artist.toLowerCase();
      lowerAlbum[s.filename] = s.album.toLowerCase();
    }

    switch (sortOrder) {
      case SongSortOrder.title:
        sorted.sort((a, b) =>
            lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!));

        break;

      case SongSortOrder.artist:
        sorted.sort((a, b) {
          int artistCompare =
              lowerArtist[a.filename]!.compareTo(lowerArtist[b.filename]!);

          if (artistCompare != 0) return artistCompare;

          return lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!);
        });

        break;

      case SongSortOrder.album:
        sorted.sort((a, b) {
          int albumCompare =
              lowerAlbum[a.filename]!.compareTo(lowerAlbum[b.filename]!);

          if (albumCompare != 0) return albumCompare;

          return lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!);
        });

        break;

      case SongSortOrder.dateAdded:
        sorted.sort((a, b) {
          final dateAddedA = a.createdEpochSec ?? a.mtime ?? 0;
          final dateAddedB = b.createdEpochSec ?? b.mtime ?? 0;
          return dateAddedB.compareTo(dateAddedA); // Newest first
        });

        break;

      case SongSortOrder.playCount:
        sorted.sort((a, b) {
          final countA = playCounts?[a.filename] ?? a.playCount;
          final countB = playCounts?[b.filename] ?? b.playCount;
          return countB.compareTo(countA);
        });
        break;

      case SongSortOrder.recommended:
        if (userData == null || shuffleConfig == null) {
          sorted.sort((a, b) {
            final titleA = lowerTitle[a.filename]!;
            final titleB = lowerTitle[b.filename]!;
            return titleA.compareTo(titleB);
          });
          break;
        }

        int maxPlayCount = 0;
        if (playCounts != null && playCounts.isNotEmpty) {
          maxPlayCount = playCounts.values.fold(0, max);
        }

        double calculateScore(Song song) {
          double weight = 1.0;
          final count = playCounts?[song.filename] ?? 0;

          if (userData.isFavorite(song.filename)) {
            if (shuffleConfig.personality == ShufflePersonality.consistent) {
              weight *= 1.4;
            } else if (shuffleConfig.personality ==
                ShufflePersonality.explorer) {
              weight *= 1.12;
            } else {
              weight *= shuffleConfig.favoriteMultiplier;
            }
          }

          if (userData.isSuggestLess(song.filename)) {
            weight *= 0.2;
          }

          if (shuffleConfig.personality == ShufflePersonality.explorer) {
            if (count == 0) {
              weight *= 1.2;
            }
          } else if (shuffleConfig.personality ==
              ShufflePersonality.consistent) {
            int threshold = 10;
            if (maxPlayCount < 10) {
              threshold = max(1, (maxPlayCount * 0.7).floor());
            } else if (maxPlayCount < 20) {
              threshold = 5;
            }
            if (count >= threshold && count > 0) {
              weight *= 1.3;
            }
          }

          return weight;
        }

        sorted.sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));
        break;

      case SongSortOrder.songDate:
        sorted.sort((a, b) {
          final songDateA = a.songDateEpochSec ?? 0;
          final songDateB = b.songDateEpochSec ?? 0;
          return songDateB.compareTo(songDateA); // Newest release first
        });
        break;
    }

    return sorted;
  }

  static LibraryFolderContent getFolderContent({
    required List<Song> allSongs,
    required String currentFullPath,
    SongSortOrder sortOrder = SongSortOrder.title,
    UserDataState? userData,
    ShuffleConfig? shuffleConfig,
    Map<String, int>? playCounts,
  }) {
    // Filter songs in the current path (or subpaths)

    final root = normalizePath(currentFullPath);
    final allSongsInFolder =
        allSongs.where((s) => isUnder(root, s.url)).toList();

    final Set<String> subFolders = {};

    final List<Song> immediateSongs = [];

    final Map<String, List<Song>> subFolderSongsMap = {};

    for (var song in allSongsInFolder) {
      final relativeToCurrent = p.relative(normalizePath(song.url), from: root);

      final parts = p.split(relativeToCurrent);

      if (parts.length == 1) {
        // It's a song in the current folder

        immediateSongs.add(song);
      } else {
        // It's in a subfolder

        final subFolderName = parts[0];

        subFolders.add(subFolderName);

        subFolderSongsMap.putIfAbsent(subFolderName, () => []).add(song);
      }
    }

    final sortedSubFolders = subFolders.toList()..sort();

    final sortedImmediateSongs = sortSongs(
      immediateSongs,
      sortOrder,
      userData: userData,
      shuffleConfig: shuffleConfig,
      playCounts: playCounts,
    );

    return LibraryFolderContent(
      subFolders: sortedSubFolders,
      immediateSongs: sortedImmediateSongs,
      allSongsInFolder: allSongsInFolder,
      subFolderSongs: subFolderSongsMap,
    );
  }

  static Map<String, List<Song>> groupByArtist(List<Song> songs) {
    final Map<String, List<Song>> artistMap = {};
    for (var song in songs) {
      final artist = song.artist.isEmpty ? 'Unknown Artist' : song.artist;
      artistMap.putIfAbsent(artist, () => []).add(song);
    }
    for (var artist in artistMap.keys) {
      final songs = artistMap[artist]!;
      final lowerAlbum = <String, String>{};
      final lowerTitle = <String, String>{};
      for (final s in songs) {
        lowerAlbum[s.filename] = s.album.toLowerCase();
        lowerTitle[s.filename] = s.title.toLowerCase();
      }
      songs.sort((a, b) {
        int albumCompare =
            lowerAlbum[a.filename]!.compareTo(lowerAlbum[b.filename]!);
        if (albumCompare != 0) return albumCompare;
        return lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!);
      });
    }
    return artistMap;
  }

  static Map<String, List<Song>> groupByAlbum(List<Song> songs) {
    final Map<String, List<Song>> albumMap = {};
    for (var song in songs) {
      final album = song.album.isEmpty ? 'Unknown Album' : song.album;
      albumMap.putIfAbsent(album, () => []).add(song);
    }
    for (var album in albumMap.keys) {
      final songs = albumMap[album]!;
      final lowerTitle = <String, String>{};
      for (final s in songs) {
        lowerTitle[s.filename] = s.title.toLowerCase();
      }
      songs.sort(
          (a, b) => lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!));
    }
    return albumMap;
  }
}

import 'package:path/path.dart' as p;
import '../models/song.dart';
import '../models/shuffle_config.dart';
import '../domain/services/shuffle_selector.dart';
import '../domain/services/song_affinity_service.dart';
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
    Map<String, double>? lastPlayedTimestamps,
    Map<String, SongAffinity>? affinities,
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
        // Ranks by the same affinity model and personality weights the shuffle
        // engine draws from, so "Recommended" and shuffle agree about taste.
        if (userData == null || shuffleConfig == null || affinities == null) {
          sorted.sort((a, b) {
            final titleA = lowerTitle[a.filename]!;
            final titleB = lowerTitle[b.filename]!;
            return titleA.compareTo(titleB);
          });
          break;
        }

        final weights = ShuffleWeights.forPersonality(shuffleConfig);

        // Score once per song rather than inside the comparator, which would
        // recompute it O(N log N) times.
        final scores = <String, double>{
          for (final song in sorted)
            song.filename: scoreCandidate(
              ShuffleCandidate<Song>(
                payload: song,
                artist: song.artist,
                album: song.album,
                affinity: affinities[song.filename] ?? SongAffinity.unknown,
                isFavorite: userData.isFavorite(song.filename),
                isSuggestLess: userData.isSuggestLess(song.filename),
              ),
              weights,
            ),
        };

        sorted.sort((a, b) {
          final compare = scores[b.filename]!.compareTo(scores[a.filename]!);
          if (compare != 0) return compare;
          return lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!);
        });
        break;

      case SongSortOrder.songDate:
        sorted.sort((a, b) {
          final songDateA = a.songDateEpochSec ?? 0;
          final songDateB = b.songDateEpochSec ?? 0;
          return songDateB.compareTo(songDateA); // Newest release first
        });
        break;

      case SongSortOrder.recentlyPlayed:
        sorted.sort((a, b) {
          final lastPlayedA = lastPlayedTimestamps?[a.filename];
          final lastPlayedB = lastPlayedTimestamps?[b.filename];

          if (lastPlayedA != null && lastPlayedB != null) {
            return lastPlayedB.compareTo(lastPlayedA);
          }
          if (lastPlayedA != null) return -1;
          if (lastPlayedB != null) return 1;

          return lowerTitle[a.filename]!.compareTo(lowerTitle[b.filename]!);
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
    Map<String, double>? lastPlayedTimestamps,
    Map<String, SongAffinity>? affinities,
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
      lastPlayedTimestamps: lastPlayedTimestamps,
      affinities: affinities,
    );

    return LibraryFolderContent(
      subFolders: sortedSubFolders,
      immediateSongs: sortedImmediateSongs,
      allSongsInFolder: allSongsInFolder,
      subFolderSongs: subFolderSongsMap,
    );
  }

  /// Splits a multi-artist string into individual artist names.
  /// Handles formats like:
  /// - "Artist 1 & Artist 2"
  /// - "Artist 1 ft. Artist 2"
  /// - "Artist 1 feat. Artist 2"
  /// - "Artist 1, Artist 2 and Artist 3"
  /// - "Artist 1 / Artist 2"
  /// - "Artist 1 x Artist 2"
  static final RegExp _splitRegex = RegExp(
    r'\s*(?:,|&|/|;|\b(?:and|featuring|x)\b|\b(?:ft|feat|vs)\b\.?)\s*',
    caseSensitive: false,
  );

  /// Splits a multi-artist string into individual artist names.
  /// Handles formats like:
  /// - "Artist 1 & Artist 2"
  /// - "Artist 1 ft. Artist 2"
  /// - "Artist 1 feat. Artist 2"
  /// - "Artist 1, Artist 2 and Artist 3"
  /// - "Artist 1 / Artist 2"
  /// - "Artist 1 x Artist 2"
  static List<String> splitArtistNames(String artistField) {
    final trimmed = artistField.trim();
    if (trimmed.isEmpty) return [];

    final parts = trimmed
        .split(_splitRegex)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty && trimmed.isNotEmpty) {
      return [trimmed];
    }

    return parts;
  }

  static Map<String, List<Song>> groupByArtist(List<Song> songs) {
    final Map<String, List<Song>> artistMap = {};
    final Map<String, String> canonicalNames = {};

    for (final song in songs) {
      final rawArtist = song.artist.trim();
      final parsedArtists = splitArtistNames(rawArtist);
      final artists =
          parsedArtists.isEmpty ? ['Unknown Artist'] : parsedArtists;

      for (final artist in artists) {
        final cleanArtist = artist.trim();
        final lowerKey = cleanArtist.toLowerCase();
        final canonicalName =
            canonicalNames.putIfAbsent(lowerKey, () => cleanArtist);

        final list = artistMap.putIfAbsent(canonicalName, () => []);
        if (!list.contains(song)) {
          list.add(song);
        }
      }
    }

    for (final artist in artistMap.keys) {
      final songsList = artistMap[artist]!;
      final lowerAlbum = <String, String>{};
      final lowerTitle = <String, String>{};
      for (final s in songsList) {
        lowerAlbum[s.filename] = s.album.toLowerCase();
        lowerTitle[s.filename] = s.title.toLowerCase();
      }
      songsList.sort((a, b) {
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

  /// Returns sorted album names from [albumMap] with most tracks first.
  static List<String> sortAlbumsByTrackCount(Map<String, List<Song>> albumMap) {
    final keys = albumMap.keys.toList();
    keys.sort((a, b) {
      final countCompare =
          (albumMap[b]?.length ?? 0).compareTo(albumMap[a]?.length ?? 0);
      if (countCompare != 0) return countCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return keys;
  }

  /// Returns sorted artist names from [artistMap] with most tracks first.
  static List<String> sortArtistsByTrackCount(
      Map<String, List<Song>> artistMap) {
    final keys = artistMap.keys.toList();
    keys.sort((a, b) {
      final countCompare =
          (artistMap[b]?.length ?? 0).compareTo(artistMap[a]?.length ?? 0);
      if (countCompare != 0) return countCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return keys;
  }
}

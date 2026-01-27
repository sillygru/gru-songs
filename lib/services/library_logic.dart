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
  static List<Song> sortSongs(
    List<Song> songs,
    SongSortOrder sortOrder, {
    UserDataState? userData,
    ShuffleConfig? shuffleConfig,
    Map<String, int>? playCounts,
  }) {
    final sorted = List<Song>.from(songs);

    switch (sortOrder) {
      case SongSortOrder.title:
        sorted.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

        break;

      case SongSortOrder.artist:
        sorted.sort((a, b) {
          int artistCompare =
              a.artist.toLowerCase().compareTo(b.artist.toLowerCase());

          if (artistCompare != 0) return artistCompare;

          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

        break;

      case SongSortOrder.album:
        sorted.sort((a, b) {
          int albumCompare =
              a.album.toLowerCase().compareTo(b.album.toLowerCase());

          if (albumCompare != 0) return albumCompare;

          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

        break;

      case SongSortOrder.dateAdded:
        sorted.sort((a, b) {
          final mtimeA = a.mtime ?? 0;

          final mtimeB = b.mtime ?? 0;

          return mtimeB.compareTo(mtimeA); // Newest first
        });

        break;

      case SongSortOrder.playCount:
        sorted.sort(
            (a, b) => b.playCount.compareTo(a.playCount)); // Most played first

        break;

      case SongSortOrder.recommended:
        if (userData == null || shuffleConfig == null) {
          // Fallback to title if data is missing

          sorted.sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

          break;
        }

        // Calculate max play count for consistent mode logic

        int maxPlayCount = 0;

        if (playCounts != null && playCounts.isNotEmpty) {
          maxPlayCount = playCounts.values.fold(0, max);
        }

        double calculateScore(Song song) {
          double weight = 1.0;

          final count = playCounts?[song.filename] ?? 0;

          // 1. User Preferences

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

          // 2. Personality Weights

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

          // Add a very small tie-breaker based on title to keep sort stable

          double tieBreaker =
              (song.title.toLowerCase().hashCode % 1000) / 1000000.0;

          return weight + tieBreaker;
        }

        sorted.sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));

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

    final allSongsInFolder = allSongs
        .where((s) =>
            s.url == currentFullPath || p.isWithin(currentFullPath, s.url))
        .toList();

    final Set<String> subFolders = {};

    final List<Song> immediateSongs = [];

    final Map<String, List<Song>> subFolderSongsMap = {};

    for (var song in allSongsInFolder) {
      final relativeToCurrent = p.relative(song.url, from: currentFullPath);

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
    // Sort songs within each artist by album then title
    for (var artist in artistMap.keys) {
      artistMap[artist]!.sort((a, b) {
        int albumCompare =
            a.album.toLowerCase().compareTo(b.album.toLowerCase());
        if (albumCompare != 0) return albumCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
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
    // Sort songs within each album by title (or track number if we had it)
    for (var album in albumMap.keys) {
      albumMap[album]!.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return albumMap;
  }
}

import 'package:path/path.dart' as p;
import '../models/song.dart';

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
  static LibraryFolderContent getFolderContent({
    required List<Song> allSongs,
    required String currentFullPath,
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
    immediateSongs
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return LibraryFolderContent(
      subFolders: sortedSubFolders,
      immediateSongs: immediateSongs,
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

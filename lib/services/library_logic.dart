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
}

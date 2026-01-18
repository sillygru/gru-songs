import 'package:path/path.dart' as p;
import '../models/song.dart';

class LibraryFolderContent {
  final List<String> subFolders;
  final List<Song> immediateSongs;

  LibraryFolderContent({
    required this.subFolders,
    required this.immediateSongs,
  });
}

class LibraryLogic {
  static LibraryFolderContent getFolderContent({
    required List<Song> allSongs,
    required String currentFullPath,
  }) {
    // Filter songs in the current path (or subpaths)
    final folderSongs = allSongs.where((s) => 
      s.url == currentFullPath || p.isWithin(currentFullPath, s.url)
    ).toList();

    final Set<String> subFolders = {};
    final List<Song> immediateSongs = [];

    for (var song in folderSongs) {
      final relativeToCurrent = p.relative(song.url, from: currentFullPath);
      final parts = p.split(relativeToCurrent);
      
      if (parts.length == 1) {
        // It's a song in the current folder
        immediateSongs.add(song);
      } else {
        // It's in a subfolder
        subFolders.add(parts[0]);
      }
    }

    final sortedSubFolders = subFolders.toList()..sort();
    immediateSongs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return LibraryFolderContent(
      subFolders: sortedSubFolders,
      immediateSongs: immediateSongs,
    );
  }
}

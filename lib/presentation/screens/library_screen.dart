import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/gru_image.dart';
import '../widgets/song_options_menu.dart';
import '../widgets/folder_grid_image.dart';
import 'song_list_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final String? relativePath;

  const LibraryScreen({super.key, this.relativePath});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return songsAsyncValue.when(
      data: (allSongs) {
        return FutureBuilder<String?>(
          future: ref.read(storageServiceProvider).getMusicFolderPath(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return Scaffold(
                appBar: AppBar(title: Text(widget.relativePath ?? 'Library')),
                body: const Center(
                    child: Text('Please select a music folder in Home first.')),
              );
            }

            final musicRoot = snapshot.data!;
            final currentFullPath = widget.relativePath == null
                ? musicRoot
                : p.join(musicRoot, widget.relativePath);

            final content = LibraryLogic.getFolderContent(
              allSongs: allSongs,
              currentFullPath: currentFullPath,
            );

            final sortedSubFolders = content.subFolders;
            final immediateSongs = content.immediateSongs;
            final isRoot = widget.relativePath == null;

            return Scaffold(
              appBar: AppBar(
                title: Text(widget.relativePath ?? 'Library'),
                actions: [
                  if (content.allSongsInFolder.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: () {
                        audioManager.shuffleAndPlay(content.allSongsInFolder,
                            isRestricted: true);
                      },
                      tooltip: 'Shuffle Folder',
                    ),
                ],
              ),
              body: ListView.builder(
                itemCount: (isRoot ? 1 : 0) +
                    sortedSubFolders.length +
                    immediateSongs.length,
                padding: const EdgeInsets.only(bottom: 100),
                itemBuilder: (context, index) {
                  int offset = 0;

                  // 1. Favorites Folder (at root only)
                  if (isRoot) {
                    if (index == 0) {
                      final favSongs = allSongs
                          .where((s) => userData.isFavorite(s.filename))
                          .toList();

                      return ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.favorite, color: Colors.red),
                        ),
                        title: const Text('Favorites',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${userData.favorites.length} songs (found in library: ${favSongs.length})'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SongListScreen(
                                title: 'Favorites',
                                songs: favSongs,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    offset = 1;
                  }

                  final folderIndex = index - offset;
                  if (folderIndex < sortedSubFolders.length) {
                    final folderName = sortedSubFolders[folderIndex];
                    final folderRelativePath = widget.relativePath == null
                        ? folderName
                        : p.join(widget.relativePath!, folderName);
                    final folderSongs =
                        content.subFolderSongs[folderName] ?? [];

                    return ListTile(
                      leading: FolderGridImage(songs: folderSongs),
                      title: Text(folderName),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LibraryScreen(relativePath: folderRelativePath),
                          ),
                        );
                      },
                    );
                  }

                  final songIndex = folderIndex - sortedSubFolders.length;
                  final song = immediateSongs[songIndex];
                  final isSuggestLess = userData.isSuggestLess(song.filename);

                  return ListTile(
                    leading: Hero(
                      tag: 'lib_art_${song.url}_${widget.relativePath}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GruImage(
                          url: song.coverUrl ?? '',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: const Icon(Icons.music_note),
                        ),
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSuggestLess ? Colors.grey : null,
                        decoration:
                            isSuggestLess ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: isSuggestLess ? Colors.grey : null),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        showSongOptionsMenu(
                            context, ref, song.filename, song.title,
                            song: song);
                      },
                    ),
                    onTap: () {
                      audioManager.playSong(song, contextQueue: immediateSongs);
                    },
                  );
                },
              ),
            );
          },
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(widget.relativePath ?? 'Library')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Scaffold(
        appBar: AppBar(title: Text(widget.relativePath ?? 'Library')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

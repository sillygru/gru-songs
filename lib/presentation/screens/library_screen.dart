import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/gru_image.dart';
import '../widgets/song_options_menu.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.relativePath ?? 'Library'),
      ),
      body: songsAsyncValue.when(
        data: (allSongs) {
          return FutureBuilder<String?>(
            future: ref.read(storageServiceProvider).getMusicFolderPath(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const Center(
                    child: Text('Please select a music folder in Home first.'));
              }

              final musicRoot = snapshot.data!;
              final currentFullPath = widget.relativePath == null
                  ? musicRoot
                  : p.join(musicRoot, widget.relativePath);

              // Favorites is only shown at the root
              final isRoot = widget.relativePath == null;

              final content = LibraryLogic.getFolderContent(
                allSongs: allSongs,
                currentFullPath: currentFullPath,
              );

              final sortedSubFolders = content.subFolders;
              final immediateSongs = content.immediateSongs;

              return ListView.builder(
                itemCount: (isRoot ? 1 : 0) +
                    sortedSubFolders.length +
                    immediateSongs.length,
                padding: const EdgeInsets.only(bottom: 100),
                itemBuilder: (context, index) {
                  int offset = 0;

                  // 1. Favorites Folder (at root only)
                  if (isRoot) {
                    if (index == 0) {
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
                            '${userData.favorites.length} songs (found in library: ${allSongs.where((s) => userData.isFavorite(s.filename)).length})'),
                        onTap: () {
                          final favSongs = allSongs
                              .where((s) => userData.isFavorite(s.filename))
                              .toList();
                          debugPrint(
                              'Library: userData.favorites count: ${userData.favorites.length}');
                          if (userData.favorites.isNotEmpty) {
                            debugPrint(
                                'Library: userData.favorites first 3: ${userData.favorites.take(3).toList()}');
                          }
                          if (allSongs.isNotEmpty) {
                            debugPrint(
                                'Library: first song filename: ${allSongs.first.filename}');
                          }
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

                    return ListTile(
                      leading: const Icon(Icons.folder,
                          size: 40, color: Colors.amber),
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
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

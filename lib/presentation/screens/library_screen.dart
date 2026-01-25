import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../../services/audio_player_manager.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_options_menu.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/song_list_item.dart';
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
    final isRoot = widget.relativePath == null;

    if (!isRoot) {
      return songsAsyncValue.when(
        data: (allSongs) =>
            _buildFolderView(context, allSongs, userData, audioManager),
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                floating: true,
                snap: true,
                pinned: true,
                title: const Text('Library',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                actions: [
                  songsAsyncValue.when(
                    data: (songs) => IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: () {
                        if (songs.isNotEmpty) {
                          audioManager.shuffleAndPlay(songs,
                              isRestricted: false);
                        }
                      },
                      tooltip: 'Shuffle All',
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Folders'),
                    Tab(text: 'Artists'),
                    Tab(text: 'Albums'),
                  ],
                ),
              ),
            ];
          },
          body: songsAsyncValue.when(
            data: (allSongs) => TabBarView(
              children: [
                _buildFolderView(context, allSongs, userData, audioManager),
                _buildArtistsView(context, allSongs),
                _buildAlbumsView(context, allSongs),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderView(BuildContext context, List<Song> allSongs,
      UserDataState userData, AudioPlayerManager audioManager) {
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

        final content = LibraryLogic.getFolderContent(
          allSongs: allSongs,
          currentFullPath: currentFullPath,
        );

        final sortedSubFolders = content.subFolders;
        final immediateSongs = content.immediateSongs;
        final isRoot = widget.relativePath == null;
        final playlists = userData.playlists;

        Widget folderIndexBuilder(BuildContext context, int index) {
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
                    borderRadius: BorderRadius.circular(12),
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

            // 2. Playlists (at root only)
            if (index - offset < playlists.length) {
              final playlist = playlists[index - offset];
              final playlistSongs = allSongs
                  .where((s) =>
                      playlist.songs.any((ps) => ps.songFilename == s.filename))
                  .toList();

              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: FolderGridImage(songs: playlistSongs),
                  ),
                ),
                title: Text(playlist.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${playlist.songs.length} songs (${playlistSongs.length} found in library)'),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    // Show playlist options (Delete)
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              title: const Text('Delete Playlist',
                                  style: TextStyle(color: Colors.red)),
                              onTap: () {
                                Navigator.pop(context);
                                ref
                                    .read(userDataProvider.notifier)
                                    .deletePlaylist(playlist.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SongListScreen(
                        title: playlist.name,
                        songs: playlistSongs,
                        playlistId: playlist.id,
                      ),
                    ),
                  );
                },
              );
            }
            offset += playlists.length;
          }

          final folderIndex = index - offset;
          if (folderIndex < sortedSubFolders.length) {
            final folderName = sortedSubFolders[folderIndex];
            final folderRelativePath = widget.relativePath == null
                ? folderName
                : p.join(widget.relativePath!, folderName);
            final folderSongs = content.subFolderSongs[folderName] ?? [];

            return ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: FolderGridImage(songs: folderSongs),
              ),
              title: Text(folderName,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('${folderSongs.length} items'),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  showFolderOptionsMenu(
                      context, ref, folderName, folderRelativePath);
                },
              ),
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
          final isPlaying =
              audioManager.currentSongNotifier.value?.filename == song.filename;

          return SongListItem(
            song: song,
            isPlaying: isPlaying,
            heroTagPrefix: 'library_${widget.relativePath ?? 'root'}',
            onTap: () {
              audioManager.playSong(song, contextQueue: immediateSongs);
            },
          );
        }

        final itemCount = (isRoot ? (1 + playlists.length) : 0) +
            sortedSubFolders.length +
            immediateSongs.length;

        if (isRoot) {
          return ListView.builder(
            itemCount: itemCount,
            padding: const EdgeInsets.only(bottom: 100),
            itemBuilder: folderIndexBuilder,
          );
        } else {
          return Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
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
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    folderIndexBuilder,
                    childCount: itemCount,
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildArtistsView(BuildContext context, List<Song> allSongs) {
    final artistMap = LibraryLogic.groupByArtist(allSongs);
    final sortedArtists = artistMap.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      shrinkWrap: true,
      itemCount: sortedArtists.length,
      itemBuilder: (context, index) {
        final artist = sortedArtists[index];
        final artistSongs = artistMap[artist]!;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: artist,
                  songs: artistSongs,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: FolderGridImage(songs: artistSongs),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${artistSongs.length} songs',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsView(BuildContext context, List<Song> allSongs) {
    final albumMap = LibraryLogic.groupByAlbum(allSongs);
    final sortedAlbums = albumMap.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      shrinkWrap: true,
      itemCount: sortedAlbums.length,
      itemBuilder: (context, index) {
        final album = sortedAlbums[index];
        final albumSongs = albumMap[album]!;
        final artist =
            albumSongs.isNotEmpty ? albumSongs[0].artist : 'Unknown Artist';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: album,
                  songs: albumSongs,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: FolderGridImage(songs: albumSongs),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                artist,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

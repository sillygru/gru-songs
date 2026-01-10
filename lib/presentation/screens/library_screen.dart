import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/providers.dart';
import '../../models/song.dart';
import 'playlist_detail_screen.dart';
import 'add_songs_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final songsAsync = ref.watch(songsProvider);
    final apiService = ref.watch(apiServiceProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_to_photos_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddSongsScreen()),
              );
            },
            tooltip: 'Add Songs',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Your Playlists',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                  // Favorites is always the first item
                  if (index == 0) {
                    return ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.favorite, color: Colors.red, size: 30),
                      ),
                      title: const Text('Favorites'),
                      subtitle: Text('${userData.favorites.length} songs'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PlaylistDetailScreen(playlistId: '__favorites__'),
                          ),
                        );
                      },
                    );
                  }

                  final playlist = userData.playlists[index - 1];
                  Widget leading = const Icon(Icons.library_music, size: 40);
                  if (playlist.songs.isNotEmpty && songsAsync.hasValue) {
                    final firstSongFilename = playlist.songs.first.filename;
                    final song = songsAsync.value!.firstWhere(
                      (s) => s.filename == firstSongFilename,
                      orElse: () => songsAsync.value!.first,
                    );
                    if (song.coverUrl != null) {
                      leading = ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: apiService.getFullUrl(song.coverUrl!),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.music_note),
                        ),
                      );
                    }
                  }

                  return ListTile(
                    leading: leading,
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songs.length} songs'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                        ),
                      );
                    },
                  );
                },
                childCount: userData.playlists.length + 1,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Most Played',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          songsAsync.when(
            data: (songs) {
              final sortedSongs = List<Song>.from(songs)
                ..sort((a, b) => b.playCount.compareTo(a.playCount));
              final mostPlayed = sortedSongs.take(10).toList();

              if (mostPlayed.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('Start listening to see your most played songs!'),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = mostPlayed[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: song.coverUrl != null
                              ? apiService.getFullUrl(song.coverUrl!)
                              : apiService.getFullUrl('/stream/cover.jpg'),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.music_note),
                        ),
                      ),
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      trailing: Text('${song.playCount} plays'),
                      onTap: () {
                        final songIndex = songs.indexOf(song);
                        if (songIndex != -1) {
                          audioManager.player.seek(Duration.zero, index: songIndex);
                          audioManager.player.play();
                        }
                      },
                    );
                  },
                  childCount: mostPlayed.length,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => SliverToBoxAdapter(
              child: Center(child: Text('Error: $err')),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

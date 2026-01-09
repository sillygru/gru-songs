import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import 'playlist_detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  void _showSongOptionsMenu(BuildContext context, WidgetRef ref, song, userData) {
    final isFavorite = userData.favorites.contains(song.filename);
    final isSuggestLess = userData.suggestLess.contains(song.filename);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text("Play Next"),
                onTap: () {
                  ref.read(audioPlayerManagerProvider).addSongToQueue(song, playNext: true);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to play next"), duration: Duration(seconds: 1)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text("Add to Queue"),
                onTap: () {
                  ref.read(audioPlayerManagerProvider).addSongToQueue(song, playNext: false);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to queue"), duration: Duration(seconds: 1)));
                },
              ),
              ListTile(
                leading: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : null),
                title: Text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text("Add to new playlist"),
                onTap: () async {
                  Navigator.pop(context);
                  final nameController = TextEditingController();
                  final newName = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("New Playlist"),
                      content: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(hintText: "Playlist Name"),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                        TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text("Create")),
                      ],
                    ),
                  );
                  if (newName != null && newName.isNotEmpty) {
                    final newPlaylist = await ref.read(userDataProvider.notifier).createPlaylist(newName);
                    if (newPlaylist != null) {
                      await ref.read(userDataProvider.notifier).addSongToPlaylist(newPlaylist.id, song.filename);
                    }
                  }
                },
              ),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == song.filename);
                if (isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text("Add to ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).addSongToPlaylist(p.id, song.filename);
                    Navigator.pop(context);
                  },
                );
              }),
              ...userData.playlists.map((p) {
                final isInPlaylist = p.songs.any((s) => s.filename == song.filename);
                if (!isInPlaylist) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text("Remove from ${p.name}"),
                  onTap: () {
                    ref.read(userDataProvider.notifier).removeSongFromPlaylist(p.id, song.filename);
                    Navigator.pop(context);
                  },
                );
              }),
              ListTile(
                leading: Icon(isSuggestLess ? Icons.thumb_up : Icons.thumb_down_outlined, color: isSuggestLess ? Colors.orange : null),
                title: Text(isSuggestLess ? "Suggest more" : "Suggest less"),
                onTap: () {
                  ref.read(userDataProvider.notifier).toggleSuggestLess(song.filename);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
    final apiService = ref.watch(apiServiceProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final userData = ref.watch(userDataProvider);

    // Listen for data changes to initialize audio
    ref.listen(songsProvider, (previous, next) {
      next.whenData((songs) {
        if (songs.isNotEmpty && (previous == null || !previous.hasValue)) {
          audioManager.init(songs, autoSelect: true);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gru Songs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(songsProvider);
            },
          ),
        ],
      ),
      body: songsAsyncValue.when(
        data: (songs) {
          if (songs.isEmpty) {
            return const Center(child: Text('No songs found'));
          }

          final random = Random();

          // Weighted recommendation logic
          final recommendations = List<Song>.from(songs)
              .where((song) => !userData.suggestLess.contains(song.filename)) // Exclude suggest-less
              .toList();

          recommendations.sort((a, b) {
            double score(Song s) {
              // Base score from play count (logarithmic to avoid one song dominating)
              double val = log(s.playCount + 1.5) * 2.0;
              
              // Boost for favorites
              if (userData.favorites.contains(s.filename)) {
                val += 5.0;
              }
              
              // Add a "little bit of randomness" (0.0 to 4.0)
              val += random.nextDouble() * 4.0;
              
              return val;
            }
            return score(b).compareTo(score(a));
          });

          final topRecommendations = recommendations.take(10).toList();

          return CustomScrollView(
            slivers: [
              if (userData.playlists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Your Playlists',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: userData.playlists.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final playlist = userData.playlists[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                              ),
                            );
                          },
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade900,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.playlist_play, size: 40),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  playlist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Recommended for You',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: topRecommendations.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final song = topRecommendations[index];
                      return GestureDetector(
                        onTap: () {
                          final songIndex = songs.indexOf(song);
                          if (songIndex != -1) {
                            audioManager.player.seek(Duration.zero, index: songIndex);
                            audioManager.player.play();
                          }
                        },
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: song.coverUrl != null
                                      ? apiService.getFullUrl(song.coverUrl!)
                                      : apiService.getFullUrl('/stream/cover.jpg'),
                                  width: 140,
                                  height: 140,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 60),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'All Songs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = songs[index];
                    final isSuggestLess = userData.suggestLess.contains(song.filename);
                    final isFavorite = userData.favorites.contains(song.filename);

                    return ListTile(
                      enabled: true,
                      leading: Opacity(
                        opacity: isSuggestLess ? 0.5 : 1.0,
                        child: ClipRRect(
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
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: isSuggestLess ? Colors.grey : null,
                          decoration: isSuggestLess ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: TextStyle(color: isSuggestLess ? Colors.grey : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "${song.playCount}",
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: Icon(isSuggestLess
                                ? Icons.heart_broken
                                : (isFavorite ? Icons.favorite : Icons.favorite_border)),
                            color: isSuggestLess ? Colors.grey : (isFavorite ? Colors.red : null),
                            onPressed: () {
                              ref.read(userDataProvider.notifier).toggleFavorite(song.filename);
                            },
                          ),
                        ],
                      ),
                      onLongPress: () async {
                        _showSongOptionsMenu(context, ref, song, userData);
                      },
                      onTap: () {
                        audioManager.player.seek(Duration.zero, index: index);
                        audioManager.player.play();
                      },
                    );
                  },
                  childCount: songs.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  'Error: $error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(songsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

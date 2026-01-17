import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gru_image.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/song_options_menu.dart';
import 'playlist_detail_screen.dart';

import 'search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
      body: songsAsyncValue.when(
        data: (songs) {
          if (songs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off_outlined, size: 80, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 16),
                  Text('No songs found', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Upload some music or try refreshing', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );
          }

          final random = Random();

          // Weighted recommendation logic
          final recommendations = List<Song>.from(songs);

          recommendations.sort((a, b) {
            double score(Song s) {
              // Base score from play count
              double val = log(s.playCount + 1.5) * 2.0;
              
              // Boost for favorites
              if (userData.favorites.contains(s.filename)) {
                val += 5.0;
              }

              // Heavy penalty for suggest-less (but not absolute block)
              if (userData.suggestLess.contains(s.filename)) {
                val -= 10.0;
              }
              
              // Add randomness
              val += random.nextDouble() * 4.0;
              
              return val;
            }
            return score(b).compareTo(score(a));
          });

          final topRecommendations = recommendations.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(songsProvider.notifier).refresh(),
                ref.read(userDataProvider.notifier).refresh(),
              ]);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  title: const Text('Gru Songs'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    onPressed: () {
                      if (songs.isNotEmpty) {
                        audioManager.shuffleAndPlay(songs);
                      }
                    },
                    tooltip: 'Shuffle All',
                  ),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'Your Playlists',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 140,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: userData.playlists.length + 1,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PlaylistDetailScreen(playlistId: '__favorites__'),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                Card(
                                  elevation: 4,
                                  shadowColor: Colors.red.withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [Colors.red.shade800, Colors.red.shade900],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.favorite, size: 48, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Favorites',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final playlist = userData.playlists[index - 1];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade900],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.playlist_play, size: 48, color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  playlist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
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
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Text(
                    'Recommended for You',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: topRecommendations.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final song = topRecommendations[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: GestureDetector(
                          onTap: () {
                          audioManager.playSong(song, contextQueue: topRecommendations);
                        },
                          child: SizedBox(
                            width: 150,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: 'art_${song.filename}',
                                  child: Card(
                                    elevation: 6,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    clipBehavior: Clip.antiAlias,
                                    child: GruImage(
                                      url: song.coverUrl != null
                                          ? apiService.getFullUrl(song.coverUrl!)
                                          : apiService.getFullUrl('/stream/cover.jpg'),
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                      errorWidget: Container(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Text(
                    'All Songs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = songs[index];
                    final isSuggestLess = userData.suggestLess.contains(song.filename);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Hero(
                        tag: 'list_art_${song.filename}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                                                  child: GruImage(
                                                    url: song.coverUrl != null
                                                        ? apiService.getFullUrl(song.coverUrl!)
                                                        : apiService.getFullUrl('/stream/cover.jpg'),
                                                    width: 56,
                                                    height: 56,
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
                          fontWeight: FontWeight.w500,
                          color: isSuggestLess ? Colors.grey : null,
                          decoration: isSuggestLess ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isSuggestLess ? Colors.grey : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (song.playCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${song.playCount}",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () {
                              showSongOptionsMenu(context, ref, song.filename, song.title, song: song);
                            },
                          ),
                        ],
                      ),
                      onLongPress: () {
                        showSongOptionsMenu(context, ref, song.filename, song.title, song: song);
                      },
                      onTap: () {
                        audioManager.playSong(song, contextQueue: songs);
                      },
                    );
                  },
                  childCount: songs.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                          ],
                        ),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(songsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
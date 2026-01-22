import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gru_image.dart';
import '../widgets/song_list_item.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import 'song_list_screen.dart';

import 'search_screen.dart';

import 'package:file_picker/file_picker.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _selectMusicFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setMusicFolderPath(selectedDirectory);
      ref.invalidate(songsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);
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
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_off_outlined,
                        size: 80,
                        color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(height: 16),
                    Text('No songs found',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Select your music folder to start listening offline.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _selectMusicFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select Music Folder'),
                    ),
                  ],
                ),
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
              if (userData.isFavorite(s.filename)) {
                val += 5.0;
              }

              // Heavy penalty for suggest-less (but not absolute block)
              if (userData.isSuggestLess(s.filename)) {
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
                  title: const Text('Gru Songs',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: () {
                        if (songs.isNotEmpty) {
                          audioManager.shuffleAndPlay(songs,
                              isRestricted: false);
                        }
                      },
                      tooltip: 'Shuffle All',
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SearchScreen()),
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Text(
                      'Library',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildLibraryCard(
                          context,
                          'Favorites',
                          Icons.favorite,
                          Colors.redAccent,
                          () {
                            final favSongs = songs
                                .where((s) => userData.isFavorite(s.filename))
                                .toList();
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
                        ),
                        // Add more quick links if needed here
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Text(
                      'Recommended',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 240,
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
                              audioManager.playSong(song,
                                  contextQueue: topRecommendations);
                            },
                            child: SizedBox(
                              width: 160,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Hero(
                                    tag: 'art_${song.filename}',
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: GruImage(
                                            url: song.coverUrl ?? '',
                                            fit: BoxFit.cover,
                                            errorWidget: Container(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: const Center(
                                                  child: Icon(
                                                      Icons.broken_image,
                                                      color: Colors.grey)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
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
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'All Songs',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        Text(
                          '${songs.length} songs',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = songs[index];
                      // We don't need detailed isPlaying check here for list performance,
                      // or we can add it if we want to highlight currently playing song.
                      // For now passing false or check simple equality
                      final isPlaying =
                          audioManager.currentSongNotifier.value?.filename ==
                              song.filename;

                      return SongListItem(
                        song: song,
                        isPlaying: isPlaying,
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
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

  Widget _buildLibraryCard(BuildContext context, String title, IconData icon,
      Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: color.withValues(alpha: 0.1), width: 1),
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

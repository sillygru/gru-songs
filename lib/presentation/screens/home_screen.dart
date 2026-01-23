import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gru_image.dart';
import '../widgets/song_list_item.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../providers/providers.dart';

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
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final songsAsyncValue = ref.watch(songsProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);

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

          final topRecommendations = ref.watch(recommendationsProvider);

          // Initial generation of recommendations if empty
          if (topRecommendations.isEmpty && songs.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ref.read(recommendationsProvider).isEmpty) {
                ref
                    .read(recommendationsProvider.notifier)
                    .generate(songs, ref.read(userDataProvider));
              }
            });
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(songsProvider.notifier).refresh(),
                ref.read(userDataProvider.notifier).refresh(),
              ]);
              // Explicitly regenerate recommendations on manual refresh
              final updatedSongs = ref.read(songsProvider).value ?? [];
              final updatedUserData = ref.read(userDataProvider);
              ref
                  .read(recommendationsProvider.notifier)
                  .generate(updatedSongs, updatedUserData);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
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
                        heroTagPrefix: 'all_songs',
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
}

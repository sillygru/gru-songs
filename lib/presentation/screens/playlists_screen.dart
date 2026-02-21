import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
import 'song_list_screen.dart';
import 'select_songs_screen.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final userData = ref.watch(userDataProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search playlists...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Playlists'),
        centerTitle: true,
        leading: _isSearching
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            icon: Icon(_isSearching ? Icons.close : Icons.search),
          ),
          IconButton(
            onPressed: () => _showMoodMixGenerator(context, ref, songsAsync),
            icon: const Icon(Icons.mood_rounded),
            tooltip: 'Mood Mix',
          ),
          IconButton(
            onPressed: () => _createPlaylist(context, ref, songsAsync),
            icon: const Icon(Icons.add),
            tooltip: 'Create Playlist',
          ),
        ],
      ),
      body: songsAsync.when(
        data: (songs) {
          var playlists =
              userData.playlists.where((p) => !p.isRecommendation).toList();

          if (_searchQuery.isNotEmpty) {
            playlists = playlists
                .where((p) =>
                    p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();
          }

          if (playlists.isEmpty && _searchQuery.isEmpty) {
            return _buildEmptyState(context, colorScheme, songsAsync);
          }

          if (playlists.isEmpty && _searchQuery.isNotEmpty) {
            return const Center(child: Text('No matching playlists found'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: playlists.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () =>
                        _showMoodMixGenerator(context, ref, songsAsync),
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.mood_rounded, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mood Mix',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text('Generate a playlist from selected moods'),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final playlist = playlists[index - 1];
              final playlistSongs = songs
                  .where((s) =>
                      playlist.songs.any((ps) => ps.songFilename == s.filename))
                  .toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
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
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FolderGridImage(songs: playlistSongs),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              CollectionDurationDisplay(
                                songs: playlistSongs,
                                showSongCount: true,
                                compact: true,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Created ${_formatDate(playlist.createdAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showPlaylistOptions(
                            context,
                            ref,
                            playlist.id,
                            playlist.name,
                          ),
                          icon: const Icon(Icons.more_vert),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    AsyncValue<List<Song>> songsAsync,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_outlined,
            size: 100,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No playlists yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first playlist to get started',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _createPlaylist(context, ref, songsAsync),
            icon: const Icon(Icons.add),
            label: const Text('Create Playlist'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showMoodMixGenerator(context, ref, songsAsync),
            icon: const Icon(Icons.mood_rounded),
            label: const Text('Mood Mix'),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Song>> songsAsync,
  ) async {
    final songs = songsAsync.value;
    if (songs == null || songs.isEmpty) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectSongsScreen(
          songs: songs,
          title: 'Create Playlist',
          isMerging: false,
          actionLabel: 'Create Playlist',
          minSelection: 1,
        ),
      ),
    );

    if (result != null && context.mounted) {
      final selected = result['filenames'] as List<String>;
      if (selected.isNotEmpty) {
        final name = await _showNameDialog(context);
        if (name != null && name.isNotEmpty && context.mounted) {
          await ref
              .read(userDataProvider.notifier)
              .createPlaylist(name, selected.first);
          // Add remaining songs
          for (int i = 1; i < selected.length; i++) {
            await ref.read(userDataProvider.notifier).addSongToPlaylist(
                  ref.read(userDataProvider).playlists.first.id,
                  selected[i],
                );
          }
        }
      }
    }
  }

  Future<void> _showMoodMixGenerator(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Song>> songsAsync,
  ) async {
    final songs = songsAsync.value;
    if (songs == null || songs.isEmpty) return;
    final userData = ref.read(userDataProvider);
    if (userData.moodTags.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No moods available. Tag some songs first.')),
        );
      }
      return;
    }

    final selectedMoodIds = <String>{};
    double length = 25;
    double diversity = 0.65;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mood Mix',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: userData.moodTags.map((mood) {
                      final selected = selectedMoodIds.contains(mood.id);
                      return FilterChip(
                        label: Text(mood.name),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() {
                            if (selected) {
                              selectedMoodIds.remove(mood.id);
                            } else {
                              selectedMoodIds.add(mood.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('Tracks: ${length.round()}'),
                  Slider(
                    value: length,
                    min: 10,
                    max: 60,
                    divisions: 10,
                    label: length.round().toString(),
                    onChanged: (value) => setModalState(() => length = value),
                  ),
                  Text('Diversity: ${(diversity * 100).round()}%'),
                  Slider(
                    value: diversity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: '${(diversity * 100).round()}%',
                    onChanged: (value) =>
                        setModalState(() => diversity = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedMoodIds.isEmpty
                          ? null
                          : () async {
                              final generated = await ref
                                  .read(userDataProvider.notifier)
                                  .generateMoodMix(
                                    moodIds: selectedMoodIds.toList(),
                                    length: length.round(),
                                    diversity: diversity,
                                  );
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (generated.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('No songs match those moods')),
                                  );
                                }
                                return;
                              }
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SongListScreen(
                                      title: 'Mood Mix',
                                      songs: generated,
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Generate'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playlist Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    String playlistName,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref, playlistId, playlistName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                ref.read(userDataProvider.notifier).deletePlaylist(playlistId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String playlistId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await ref
          .read(userDataProvider.notifier)
          .updatePlaylistName(playlistId, newName);
    }
  }

  String _formatDate(double timestamp) {
    final date =
        DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7} weeks ago';

    return '${date.month}/${date.year}';
  }
}

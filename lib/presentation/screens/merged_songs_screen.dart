import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../widgets/album_art_image.dart';

class MergedSongsScreen extends ConsumerWidget {
  const MergedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merged Songs',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: songsAsync.when(
        data: (songs) => _buildContent(context, ref, userData, songs),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref,
      UserDataState userData, List<Song> songs) {
    if (userData.mergedGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.merge_type,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No merged songs yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select multiple songs in your library\nand tap "Merge" to group them',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Merge different versions of the same song (remixes, live versions, etc.) so they\'re treated as one during shuffle. Favorites and suggest-less settings remain independent for each song.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
              ),
            ),
          ],
        ),
      );
    }

    // Build a map of filename to song for quick lookup
    final songMap = {for (var s in songs) s.filename: s};

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: userData.mergedGroups.length,
      itemBuilder: (context, index) {
        final entry = userData.mergedGroups.entries.elementAt(index);
        final groupId = entry.key;
        final filenames = entry.value;
        final groupSongs = filenames
            .map((f) => songMap[f])
            .where((s) => s != null)
            .cast<Song>()
            .toList();

        if (groupSongs.isEmpty) {
          return const SizedBox.shrink();
        }

        return _MergeGroupCard(
          groupId: groupId,
          songs: groupSongs,
          onUnmerge: (song) => _showUnmergeDialog(context, ref, song),
          onDeleteGroup: () => _showDeleteGroupDialog(context, ref, groupId),
        );
      },
    );
  }

  Future<void> _showUnmergeDialog(
      BuildContext context, WidgetRef ref, Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unmerge Song'),
        content: Text('Remove "${song.title}" from this merge group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unmerge'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(userDataProvider.notifier).unmergeSong(song.filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${song.title}" unmerged')),
        );
      }
    }
  }

  Future<void> _showDeleteGroupDialog(
      BuildContext context, WidgetRef ref, String groupId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Merge Group'),
        content: const Text('Unmerge all songs in this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unmerge All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(userDataProvider.notifier).deleteMergedGroup(groupId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merge group deleted')),
        );
      }
    }
  }
}

class _MergeGroupCard extends StatelessWidget {
  final String groupId;
  final List<Song> songs;
  final Function(Song) onUnmerge;
  final VoidCallback onDeleteGroup;

  const _MergeGroupCard({
    required this.groupId,
    required this.songs,
    required this.onUnmerge,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.merge_type,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Merge Group',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                Text(
                  '${songs.length} songs',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDeleteGroup,
                  tooltip: 'Unmerge all',
                ),
              ],
            ),
          ),
          // Song list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
            itemBuilder: (context, index) {
              final song = songs[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AlbumArtImage(
                    url: song.coverUrl ?? '',
                    filename: song.filename,
                    width: 40,
                    height: 40,
                    memCacheWidth: 80,
                    memCacheHeight: 80,
                  ),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off, size: 20),
                  onPressed: () => onUnmerge(song),
                  tooltip: 'Unmerge',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

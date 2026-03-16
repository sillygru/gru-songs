import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/queue_snapshot.dart';
import '../../models/song.dart';
import '../../providers/queue_history_provider.dart';
import '../../providers/providers.dart';
import '../widgets/album_art_image.dart';
import 'player_screen.dart';

class QueueHistoryScreen extends ConsumerWidget {
  const QueueHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(queueHistoryProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final currentQueue = ref.watch(
      audioPlayerManagerProvider.select((m) => m.queueNotifier.value),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue History'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => ref.read(queueHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_all') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear Queue History'),
                    content: const Text(
                        'Delete all saved queues? This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(queueHistoryProvider.notifier).clearAll();
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Text('Clear All History'),
              ),
            ],
          ),
        ],
      ),
      body: historyAsync.when(
        data: (snapshots) {
          if (snapshots.isEmpty && currentQueue.isEmpty) {
            return _buildEmptyState(colorScheme);
          }
          return _buildList(context, ref, snapshots, currentQueue, colorScheme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load queue history',
                  style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(queueHistoryProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.queue_music_rounded,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Queues Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Queues are saved automatically when you start playing',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<QueueSnapshot> snapshots,
    List<dynamic> currentQueue,
    ColorScheme colorScheme,
  ) {
    final audioManager = ref.read(audioPlayerManagerProvider);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: snapshots.length + (currentQueue.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (currentQueue.isNotEmpty && index == 0) {
          return _buildCurrentQueueCard(
              context, ref, currentQueue, colorScheme);
        }
        final snapshotIndex = currentQueue.isNotEmpty ? index - 1 : index;
        final snapshot = snapshots[snapshotIndex];
        return _buildSnapshotCard(
            context, ref, snapshot, audioManager, colorScheme);
      },
    );
  }

  Widget _buildCurrentQueueCard(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> queue,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        elevation: 0,
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: InkWell(
          onTap: () =>
              _showCurrentQueueDetail(context, ref, queue, colorScheme),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: colorScheme.onPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Now Playing',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSnapshotCard(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    dynamic audioManager,
    ColorScheme colorScheme,
  ) {
    return Dismissible(
      key: Key(snapshot.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) {
        ref.read(queueHistoryProvider.notifier).deleteSnapshot(snapshot.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: InkWell(
            onTap: () => _showSnapshotDetail(
                context, ref, snapshot, audioManager, colorScheme),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: colorScheme.onSecondaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 13, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              snapshot.displayDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCurrentQueueDetail(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> queue,
    ColorScheme colorScheme,
  ) {
    final songs = queue
        .map((item) {
          try {
            return item.song as Song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QueueDetailSheet(
        title: 'Now Playing',
        songs: songs,
        isCurrentQueue: true,
        colorScheme: colorScheme,
        onApply: null,
      ),
    );
  }

  void _showSnapshotDetail(
    BuildContext context,
    WidgetRef ref,
    QueueSnapshot snapshot,
    dynamic audioManager,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(
        builder: (ctx, innerRef, _) {
          final songsAsync =
              innerRef.watch(queueSnapshotSongsProvider(snapshot.id));
          return songsAsync.when(
            loading: () => Container(
              height: 200,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (songs) => _QueueDetailSheet(
              title: snapshot.name,
              songs: songs,
              isCurrentQueue: false,
              colorScheme: colorScheme,
              onApply: (whenSongEnds) {
                _applyQueue(ctx, innerRef, songs, audioManager, snapshot.source,
                    whenSongEnds);
              },
            ),
          );
        },
      ),
    );
  }

  void _applyQueue(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    dynamic audioManager,
    String source,
    bool whenSongEnds,
  ) {
    if (songs.isEmpty) return;

    if (whenSongEnds) {
      audioManager.setPendingQueueReplacement(songs, playlistId: source);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Queue of ${songs.length} tracks will play after current song'),
          action: SnackBarAction(
            label: 'Cancel',
            onPressed: audioManager.cancelPendingQueueReplacement,
          ),
        ),
      );
    } else {
      audioManager.replaceQueue(songs, playlistId: source, forceLinear: true);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Playing ${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}'),
          action: SnackBarAction(
            label: 'Open Player',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            ),
          ),
        ),
      );
    }
  }
}

class _QueueDetailSheet extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final bool isCurrentQueue;
  final ColorScheme colorScheme;
  final void Function(bool whenSongEnds)? onApply;

  const _QueueDetailSheet({
    required this.title,
    required this.songs,
    required this.isCurrentQueue,
    required this.colorScheme,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrentQueue)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Now Playing',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Song list
              Expanded(
                child: songs.isEmpty
                    ? Center(
                        child: Text(
                          'No tracks available',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: AlbumArtImage(
                                  url: song.coverUrl ?? '',
                                  width: 48,
                                  height: 48,
                                ),
                              ),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                            trailing: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Apply button (only for saved queues, not current)
              if (!isCurrentQueue && onApply != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: () => onApply!(false),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'Apply Queue Now',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => onApply!(true),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text(
                            'Apply When Current Song Ends',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

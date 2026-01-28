import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/queue_item.dart';
import 'album_art_image.dart';

class NextUpSheet extends ConsumerWidget {
  const NextUpSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return ValueListenableBuilder<List<QueueItem>>(
      valueListenable: audioManager.queueNotifier,
      builder: (context, queue, child) {
        final currentIndex = audioManager.player.currentIndex ?? -1;

        // Show up to 20 upcoming songs after current
        final upcomingQueue = queue.skip(currentIndex + 1).take(20).toList();

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Up Next',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${upcomingQueue.length} songs',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 24, endIndent: 24),
              Expanded(
                child: upcomingQueue.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.playlist_play,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text("Queue is empty",
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: upcomingQueue.length,
                        padding: const EdgeInsets.only(bottom: 24, top: 8),
                        onReorder: (oldIndex, newIndex) {
                          // Adjust indices for the full queue
                          audioManager.reorderQueue(
                            currentIndex + 1 + oldIndex,
                            currentIndex + 1 + newIndex,
                          );
                        },
                        itemBuilder: (context, index) {
                          final item = upcomingQueue[index];
                          final song = item.song;

                          return Padding(
                            key: ValueKey(item.queueId),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AlbumArtImage(
                                    url: item.song.coverUrl ?? '',
                                    filename: item.song.filename,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: item.isPriority
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (item.isPriority)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Icon(Icons.push_pin,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                      onPressed: () {
                                        audioManager.removeFromQueue(
                                            currentIndex + 1 + index);
                                      },
                                    ),
                                    Icon(Icons.drag_handle,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.5)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/queue_item.dart';
import 'gru_image.dart';

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
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Next Up',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${upcomingQueue.length} songs',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: upcomingQueue.isEmpty
                    ? const Center(child: Text('Queue is empty'))
                    : ReorderableListView.builder(
                        itemCount: upcomingQueue.length,
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

                          return ListTile(
                            key: ValueKey(item.queueId),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: GruImage(
                                url: song.coverUrl ?? '',
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              ),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: item.isPriority
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: item.isPriority
                                    ? Colors.deepPurple[200]
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
                                  const Icon(Icons.push_pin,
                                      size: 16, color: Colors.deepPurple),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    audioManager.removeFromQueue(
                                        currentIndex + 1 + index);
                                  },
                                ),
                                const Icon(Icons.drag_handle),
                              ],
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

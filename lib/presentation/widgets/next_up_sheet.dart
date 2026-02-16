import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/queue_item.dart';
import '../../services/audio_player_manager.dart';
import 'album_art_image.dart';

class NextUpSheet extends ConsumerWidget {
  const NextUpSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<List<QueueItem>>(
      valueListenable: audioManager.queueNotifier,
      builder: (context, queue, child) {
        return StreamBuilder<int?>(
          stream: audioManager.player.currentIndexStream,
          initialData: audioManager.player.currentIndex,
          builder: (context, snapshot) {
            final currentIndex = snapshot.data ?? -1;

            // Show upcoming songs after current
            final upcomingQueue = queue.skip(currentIndex + 1).toList();

            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.7),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      // Grab Handle
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Up Next',
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Text(
                                    '${upcomingQueue.length} songs remaining',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Header Actions
                            _HeaderAction(
                              icon: Icons.refresh_rounded,
                              tooltip: 'Shuffle Remaining',
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                audioManager.refreshQueue();
                              },
                            ),
                            const SizedBox(width: 8),
                            _HeaderAction(
                              icon: Icons.delete_sweep_rounded,
                              tooltip: 'Clear All',
                              onPressed: upcomingQueue.isEmpty
                                  ? null
                                  : () {
                                      _showClearConfirm(context, audioManager);
                                    },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: upcomingQueue.isEmpty
                              ? _EmptyQueue(key: const ValueKey('empty'))
                              : ReorderableListView.builder(
                                  key: const ValueKey('list'),
                                  itemCount: upcomingQueue.length,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 40),
                                  onReorder: (oldIndex, newIndex) {
                                    HapticFeedback.lightImpact();
                                    audioManager.reorderQueue(
                                      currentIndex + 1 + oldIndex,
                                      currentIndex + 1 + newIndex,
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    return _NextUpItem(
                                      key: ValueKey(
                                          upcomingQueue[index].queueId),
                                      item: upcomingQueue[index],
                                      index: index,
                                      currentIndex: currentIndex,
                                      audioManager: audioManager,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showClearConfirm(
      BuildContext context, AudioPlayerManager audioManager) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue?'),
        content: const Text(
            'This will remove all upcoming songs from the current queue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              audioManager.clearUpcoming();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

class _NextUpItem extends StatelessWidget {
  final QueueItem item;
  final int index;
  final int currentIndex;
  final AudioPlayerManager audioManager;

  const _NextUpItem({
    super.key,
    required this.item,
    required this.index,
    required this.currentIndex,
    required this.audioManager,
  });

  @override
  Widget build(BuildContext context) {
    final song = item.song;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      key: ValueKey('padding_${item.queueId}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('dismiss_${item.queueId}'),
        direction: DismissDirection.horizontal,
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            HapticFeedback.mediumImpact();
            audioManager.removeFromQueue(currentIndex + 1 + index);
          }
        },
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            HapticFeedback.lightImpact();
            audioManager.togglePriority(currentIndex + 1 + index);
            return false; // Don't dismiss
          }
          return true; // Dismiss for endToStart
        },
        background: _SwipeAction(
          color: colorScheme.primary,
          icon: item.isPriority
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          alignment: Alignment.centerLeft,
          label: item.isPriority ? 'Unpin' : 'Pin to Top',
        ),
        secondaryBackground: const _SwipeAction(
          color: Colors.redAccent,
          icon: Icons.delete_outline_rounded,
          alignment: Alignment.centerRight,
          label: 'Remove',
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.isPriority
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.03),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              leading: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AlbumArtImage(
                      url: item.song.coverUrl ?? '',
                      filename: item.song.filename,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (item.isPriority)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: colorScheme.surface, width: 2),
                        ),
                        child: const Icon(Icons.push_pin_rounded,
                            size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: item.isPriority ? colorScheme.primary : null,
                ),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              trailing: ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Alignment alignment;
  final String label;

  const _SwipeAction({
    required this.color,
    required this.icon,
    required this.alignment,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_motion_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Nothing's next",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            "Hmmmm guess you ran out of songs bro",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}

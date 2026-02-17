import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/queue_item.dart';
import '../../models/song.dart';
import '../../services/audio_player_manager.dart';
import 'album_art_image.dart' show StaticAlbumArtImage;

class NextUpSheet extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final DraggableScrollableController? sheetController;

  const NextUpSheet({
    super.key,
    this.scrollController,
    this.sheetController,
  });

  @override
  ConsumerState<NextUpSheet> createState() => _NextUpSheetState();
}

class _NextUpSheetState extends ConsumerState<NextUpSheet> {
  // Memoized queue list to prevent recalculation on every minor build
  List<QueueItem>? _cachedUpcomingQueue;
  int _cachedCurrentIndex = -1;
  int _cachedQueueLength = -1;

  void _toggleSheetSize() {
    final controller = widget.sheetController;
    if (controller == null) return;

    final currentSize = controller.size;
    final targetSize = currentSize < 0.7 ? 0.9 : 0.5;

    controller.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
    );
  }

  // Optimized manual drag for the header
  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    final controller = widget.sheetController;
    if (controller == null) return;

    final double delta = details.primaryDelta ?? 0;
    final double height = MediaQuery.of(context).size.height;
    if (height == 0) return;

    // Calculate new size directly
    final newSize = controller.size - (delta / height);
    controller.jumpTo(newSize.clamp(0.1, 0.95));
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    final controller = widget.sheetController;
    if (controller == null) return;

    final velocity = details.primaryVelocity ?? 0;
    final currentSize = controller.size;

    // Fast dismiss logic
    if (velocity > 1500 || (velocity > 0 && currentSize < 0.35)) {
      Navigator.of(context).pop();
      return;
    }

    // Snap logic
    double targetSize;
    if (velocity.abs() > 300) {
      targetSize = velocity > 0 ? 0.5 : 0.9;
    } else {
      targetSize = currentSize < 0.7 ? 0.5 : 0.9;
    }

    controller.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Grab Handle Area - Static
            GestureDetector(
              onTap: _toggleSheetSize,
              onVerticalDragUpdate: _handleHeaderDragUpdate,
              onVerticalDragEnd: _handleHeaderDragEnd,
              behavior: HitTestBehavior.translucent,
              child: SizedBox(
                width: double.infinity,
                height: 20,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // Header Area with Dynamic Content
            _NextUpHeader(
              audioManager: audioManager,
              onHeaderDragUpdate: _handleHeaderDragUpdate,
              onHeaderDragEnd: _handleHeaderDragEnd,
              onClearConfirm: () => _showClearConfirm(context, audioManager),
            ),
            // List Content - Only this part rebuilds frequently
            Expanded(
              child: ValueListenableBuilder<List<QueueItem>>(
                valueListenable: audioManager.queueNotifier,
                builder: (context, queue, child) {
                  return StreamBuilder<int?>(
                    stream: audioManager.player.currentIndexStream,
                    initialData: audioManager.player.currentIndex,
                    builder: (context, snapshot) {
                      final currentIndex = snapshot.data ?? -1;

                      // Simple cache check to avoid expensive .skip().toList() on every frame if nothing changed
                      if (_cachedUpcomingQueue == null ||
                          _cachedCurrentIndex != currentIndex ||
                          _cachedQueueLength != queue.length) {
                        _cachedUpcomingQueue =
                            queue.skip(currentIndex + 1).toList();
                        _cachedCurrentIndex = currentIndex;
                        _cachedQueueLength = queue.length;
                      }

                      final upcomingQueue = _cachedUpcomingQueue!;

                      if (upcomingQueue.isEmpty) {
                        return const _EmptyQueue();
                      }

                      return _QueueListContent(
                        upcomingQueue: upcomingQueue,
                        currentIndex: currentIndex,
                        audioManager: audioManager,
                        scrollController: widget.scrollController,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
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

class _QueueListContent extends StatelessWidget {
  final List<QueueItem> upcomingQueue;
  final int currentIndex;
  final AudioPlayerManager audioManager;
  final ScrollController? scrollController;

  const _QueueListContent({
    required this.upcomingQueue,
    required this.currentIndex,
    required this.audioManager,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // We create a prototype item for performance calculation
    final prototypeItem = upcomingQueue.isNotEmpty
        ? _NextUpItem(
            key: const ValueKey('prototype'),
            item: upcomingQueue.first,
            index: 0,
            currentIndex: 0,
            audioManager: audioManager)
        : null;

    return ReorderableListView.builder(
      itemCount: upcomingQueue.length,
      scrollController: scrollController,
      // PERFORMANCE: Helps flutter calculate scroll height without rendering everything
      prototypeItem: prototypeItem,
      cacheExtent:
          1000, // Keep more items alive in memory for smoother fast scrolling
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      // IMPORTANT: Disabling default handles prevents the whole tile from being a drag target.
      // This allows the Swipe gesture (Dismissible) to work everywhere EXCEPT the handle.
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        HapticFeedback.selectionClick();
        audioManager.reorderQueue(
          currentIndex + 1 + oldIndex,
          currentIndex + 1 + newIndex,
        );
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final double animValue =
                Curves.easeInOut.transform(animation.value);
            return Material(
              elevation: 12 * animValue,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: Transform.scale(
                scale: 1.0 + (0.02 * animValue),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final item = upcomingQueue[index];
        return RepaintBoundary(
          key: ValueKey('repaint_${item.queueId}'),
          child: _NextUpItem(
            key: ValueKey(item.queueId),
            item: item,
            index: index,
            currentIndex: currentIndex,
            audioManager: audioManager,
          ),
        );
      },
    );
  }
}

class _NextUpHeader extends StatelessWidget {
  final AudioPlayerManager audioManager;
  final void Function(DragUpdateDetails) onHeaderDragUpdate;
  final void Function(DragEndDetails) onHeaderDragEnd;
  final VoidCallback onClearConfirm;

  const _NextUpHeader({
    required this.audioManager,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onClearConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onVerticalDragUpdate: onHeaderDragUpdate,
      onVerticalDragEnd: onHeaderDragEnd,
      behavior: HitTestBehavior.translucent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<List<QueueItem>>(
                valueListenable: audioManager.queueNotifier,
                builder: (context, queue, child) {
                  return StreamBuilder<int?>(
                    stream: audioManager.player.currentIndexStream,
                    initialData: audioManager.player.currentIndex,
                    builder: (context, snapshot) {
                      final currentIndex = snapshot.data ?? -1;
                      final upcomingCount = queue.length - currentIndex - 1;
                      final displayCount =
                          upcomingCount < 0 ? 0 : upcomingCount;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Up Next',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            '$displayCount songs remaining',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _HeaderAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Shuffle Remaining',
              onPressed: () {
                HapticFeedback.mediumImpact();
                audioManager.refreshQueue();
              },
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<List<QueueItem>>(
              valueListenable: audioManager.queueNotifier,
              builder: (context, queue, child) {
                return StreamBuilder<int?>(
                  stream: audioManager.player.currentIndexStream,
                  initialData: audioManager.player.currentIndex,
                  builder: (context, snapshot) {
                    final currentIndex = snapshot.data ?? -1;
                    final hasUpcoming = queue.length > currentIndex + 1;

                    return _HeaderAction(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Clear All',
                      onPressed: hasUpcoming ? onClearConfirm : null,
                    );
                  },
                );
              },
            ),
          ],
        ),
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        color: theme.colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
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

    // We use a cleaner Dismissible setup.
    // The key ensures Flutter knows which item is being swiped.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('dismiss_${item.queueId}'),
        direction: DismissDirection.horizontal,
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.25,
          DismissDirection.endToStart: 0.25,
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
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            HapticFeedback.mediumImpact();
            audioManager.togglePriority(currentIndex + 1 + index);
            return false; // Don't remove from list, just toggle state
          }
          return true; // Allow remove
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            HapticFeedback.mediumImpact();
            audioManager.removeFromQueue(currentIndex + 1 + index);
          }
        },
        child: _buildItemContent(context, song, theme, colorScheme),
      ),
    );
  }

  Widget _buildItemContent(BuildContext context, Song song, ThemeData theme,
      ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.isPriority
              ? colorScheme.primary.withValues(alpha: 0.3)
              : Colors
                  .transparent, // Optimization: transparent instead of calc when not needed
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        // Album Art
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: StaticAlbumArtImage(
                url: song.coverUrl ?? '',
                filename: song.filename,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            if (item.isPriority)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        )
                      ]),
                  child: const Icon(Icons.push_pin_rounded,
                      size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        // Text Info
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: item.isPriority ? colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
        // The Reorder Handle
        // This is CRITICAL: ReorderableDragStartListener makes ONLY this icon
        // the trigger for dragging. The rest of the tile is free for scrolling/swiping.
        trailing: ReorderableDragStartListener(
          index: index,
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.transparent, // Increase hit area
            child: Icon(
              Icons.drag_indicator_rounded,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              size: 20,
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
    // Optimization: Pre-calculate padding based on alignment
    final isLeft = alignment == Alignment.centerLeft;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: alignment,
      padding: EdgeInsets.only(
        left: isLeft ? 24 : 0,
        right: isLeft ? 0 : 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

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
              color: colorScheme.onSurface.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.queue_music_rounded,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Nothing's next",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Add songs to keep the vibe going",
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

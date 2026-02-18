import 'dart:async';

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
    final audioManager = ref.read(audioPlayerManagerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      clipBehavior: Clip.antiAlias,
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
                    final upcomingQueue = queue.skip(currentIndex + 1).toList();

                    if (upcomingQueue.isEmpty) {
                      return const _EmptyQueue();
                    }

                    return _QueueListContent(
                      upcomingQueue: upcomingQueue,
                      currentIndex: currentIndex,
                      audioManager: audioManager,
                      scrollController: widget.scrollController,
                      onRemove: (absoluteIndex) => _handleRemoveTap(
                        context: context,
                        audioManager: audioManager,
                        absoluteIndex: absoluteIndex,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRemoveTap({
    required BuildContext context,
    required AudioPlayerManager audioManager,
    required int absoluteIndex,
  }) async {
    HapticFeedback.mediumImpact();
    await audioManager.removeFromQueue(absoluteIndex);
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
  final ValueChanged<int> onRemove;

  const _QueueListContent({
    required this.upcomingQueue,
    required this.currentIndex,
    required this.audioManager,
    this.scrollController,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: upcomingQueue.length,
      scrollController: scrollController,
      // PERFORMANCE: Fixed item height avoids constructing a prototype widget on every build
      itemExtent: 80.0,
      cacheExtent:
          400, // Reduced from 1000 — budget phones can't afford pre-rendering 15 items
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      // Keep drag reorder scoped to the explicit handle only.
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
        final absoluteIndex = currentIndex + 1 + index;
        return RepaintBoundary(
          key: ValueKey('repaint_${item.queueId}'),
          child: _NextUpItem(
            key: ValueKey(item.queueId),
            item: item,
            index: index,
            onTogglePriority: () {
              HapticFeedback.mediumImpact();
              audioManager.togglePriority(absoluteIndex);
            },
            onRemove: () => onRemove(absoluteIndex),
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
              // Single combined listener replacing two separate nests
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
                      final hasUpcoming = displayCount > 0;

                      return Row(
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
                                  '$displayCount songs remaining',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
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
                          _HeaderAction(
                            icon: Icons.delete_sweep_rounded,
                            tooltip: 'Clear All',
                            onPressed: hasUpcoming ? onClearConfirm : null,
                          ),
                        ],
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
  final VoidCallback onTogglePriority;
  final VoidCallback onRemove;

  // Pre-computed static colors to avoid per-item allocation during scroll
  static const _pinBorderOpacity = 0.3;
  static const _dragHandleOpacity = 0.2;
  static const _subtitleOpacity = 0.7;
  static const _pinShadowOpacity = 0.2;

  const _NextUpItem({
    super.key,
    required this.item,
    required this.index,
    required this.onTogglePriority,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _NextUpItemContent(
        item: item,
        index: index,
        onTogglePriority: onTogglePriority,
        onRemove: onRemove,
      ),
    );
  }
}

// Extracted into its own StatelessWidget so Flutter can diff and skip rebuilds independently
class _NextUpItemContent extends StatelessWidget {
  final QueueItem item;
  final int index;
  final VoidCallback onTogglePriority;
  final VoidCallback onRemove;

  const _NextUpItemContent({
    required this.item,
    required this.index,
    required this.onTogglePriority,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final song = item.song;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Pre-compute colors once per build rather than inline per-property
    final subtitleColor = colorScheme.onSurfaceVariant
        .withValues(alpha: _NextUpItem._subtitleOpacity);
    final borderColor = item.isPriority
        ? colorScheme.primary.withValues(alpha: _NextUpItem._pinBorderOpacity)
        : Colors.transparent;
    final titleColor = item.isPriority ? colorScheme.primary : null;
    final dragHandleColor = colorScheme.onSurfaceVariant
        .withValues(alpha: _NextUpItem._dragHandleOpacity);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                        color: Colors.black
                            .withValues(alpha: _NextUpItem._pinShadowOpacity),
                        blurRadius: 4,
                      )
                    ],
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
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: titleColor,
          ),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: subtitleColor,
            fontSize: 13,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                item.isPriority
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                color: item.isPriority ? colorScheme.primary : dragHandleColor,
                size: 20,
              ),
              tooltip: item.isPriority ? 'Unpin' : 'Pin to Top',
              onPressed: onTogglePriority,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Colors.redAccent,
              ),
              tooltip: 'Remove',
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
            ),
            ReorderableDragStartListener(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.transparent,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: dragHandleColor,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
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

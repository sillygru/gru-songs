import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/queue_item.dart';
import '../../models/song.dart';
import '../../services/audio_player_manager.dart';
import 'album_art_image.dart';

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
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                color: colorScheme.surface.withValues(alpha: 0.95),
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
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Grab Handle - Draggable with dismiss support
                    GestureDetector(
                      onTap: _toggleSheetSize,
                      onVerticalDragUpdate: (details) {
                        final controller = widget.sheetController;
                        if (controller == null) return;
                        final delta = details.primaryDelta ?? 0;
                        final newSize = controller.size -
                            (delta / MediaQuery.of(context).size.height);
                        controller.jumpTo(newSize.clamp(0.1, 0.9));
                      },
                      onVerticalDragEnd: (details) {
                        final controller = widget.sheetController;
                        if (controller == null) return;
                        final velocity = details.primaryVelocity ?? 0;
                        final currentSize = controller.size;

                        // Dismiss on fast downward swipe (>800 px/s) or if dragged below 0.25
                        if (velocity > 800 || currentSize < 0.25) {
                          Navigator.of(context).pop();
                          return;
                        }

                        // Snap to nearest point based on velocity and position
                        double targetSize;
                        if (velocity.abs() > 300) {
                          targetSize = velocity > 0 ? 0.5 : 0.9;
                        } else {
                          targetSize = currentSize < 0.7 ? 0.5 : 0.9;
                        }

                        controller.animateTo(
                          targetSize,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    // Header - Also draggable with dismiss support
                    GestureDetector(
                      onVerticalDragUpdate: (details) {
                        final controller = widget.sheetController;
                        if (controller == null) return;
                        final delta = details.primaryDelta ?? 0;
                        final newSize = controller.size -
                            (delta / MediaQuery.of(context).size.height);
                        controller.jumpTo(newSize.clamp(0.1, 0.9));
                      },
                      onVerticalDragEnd: (details) {
                        final controller = widget.sheetController;
                        if (controller == null) return;
                        final velocity = details.primaryVelocity ?? 0;
                        final currentSize = controller.size;

                        // Dismiss on fast downward swipe (>800 px/s) or if dragged below 0.25
                        if (velocity > 800 || currentSize < 0.25) {
                          Navigator.of(context).pop();
                          return;
                        }

                        double targetSize;
                        if (velocity.abs() > 300) {
                          targetSize = velocity > 0 ? 0.5 : 0.9;
                        } else {
                          targetSize = currentSize < 0.7 ? 0.5 : 0.9;
                        }

                        controller.animateTo(
                          targetSize,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      },
                      behavior: HitTestBehavior.translucent,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
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
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: upcomingQueue.isEmpty
                          ? const _EmptyQueue()
                          : _QueueListContent(
                              upcomingQueue: upcomingQueue,
                              currentIndex: currentIndex,
                              audioManager: audioManager,
                              scrollController: widget.scrollController,
                            ),
                    ),
                  ],
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
    return ReorderableListView.builder(
      itemCount: upcomingQueue.length,
      scrollController: scrollController,
      cacheExtent: 500,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      onReorder: (oldIndex, newIndex) {
        HapticFeedback.lightImpact();
        audioManager.reorderQueue(
          currentIndex + 1 + oldIndex,
          currentIndex + 1 + newIndex,
        );
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation = Tween<double>(
              begin: 0,
              end: 8,
            ).evaluate(animation);
            return Material(
              elevation: elevation,
              borderRadius: BorderRadius.circular(18),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        return _NextUpItem(
          key: ValueKey(upcomingQueue[index].queueId),
          item: upcomingQueue[index],
          index: index,
          currentIndex: currentIndex,
          audioManager: audioManager,
        );
      },
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

class _NextUpItem extends StatefulWidget {
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
  State<_NextUpItem> createState() => _NextUpItemState();
}

class _NextUpItemState extends State<_NextUpItem> {
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;
  bool _isHorizontalDrag = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.item.song;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RepaintBoundary(
      child: Padding(
        key: ValueKey('padding_${widget.item.queueId}'),
        padding: const EdgeInsets.only(bottom: 8),
        child: Listener(
          onPointerDown: (event) {
            _dragStartX = event.position.dx;
            _dragStartY = event.position.dy;
            _isDragging = true;
            _isHorizontalDrag = false;
          },
          onPointerMove: (event) {
            if (!_isDragging) return;

            final dx = event.position.dx - _dragStartX;
            final dy = event.position.dy - _dragStartY;
            final totalDistance = math.sqrt(dx * dx + dy * dy);

            if (totalDistance > 10) {
              final horizontalRatio = dx.abs() / totalDistance;
              _isHorizontalDrag = horizontalRatio > 0.6;
              setState(() {});
            }
          },
          onPointerUp: (event) {
            _isDragging = false;
          },
          onPointerCancel: (event) {
            _isDragging = false;
          },
          behavior: HitTestBehavior.translucent,
          child: _isHorizontalDrag || !_isDragging
              ? Dismissible(
                  key: ValueKey('dismiss_${widget.item.queueId}'),
                  direction: DismissDirection.horizontal,
                  dismissThresholds: const {
                    DismissDirection.startToEnd: 0.25,
                    DismissDirection.endToStart: 0.25,
                  },
                  movementDuration: const Duration(milliseconds: 200),
                  onDismissed: (direction) {
                    if (direction == DismissDirection.endToStart) {
                      widget.audioManager.removeFromQueue(
                          widget.currentIndex + 1 + widget.index);
                    }
                  },
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      widget.audioManager.togglePriority(
                          widget.currentIndex + 1 + widget.index);
                      return false;
                    }
                    return true;
                  },
                  background: _SwipeAction(
                    color: colorScheme.primary,
                    icon: widget.item.isPriority
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    alignment: Alignment.centerLeft,
                    label: widget.item.isPriority ? 'Unpin' : 'Pin to Top',
                  ),
                  secondaryBackground: const _SwipeAction(
                    color: Colors.redAccent,
                    icon: Icons.delete_outline_rounded,
                    alignment: Alignment.centerRight,
                    label: 'Remove',
                  ),
                  child: _buildItemContent(song, theme, colorScheme),
                )
              : _buildItemContent(song, theme, colorScheme),
        ),
      ),
    );
  }

  Widget _buildItemContent(
      Song song, ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.item.isPriority
              ? colorScheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.03),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AlbumArtImage(
                  url: widget.item.song.coverUrl ?? '',
                  filename: widget.item.song.filename,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              if (widget.item.isPriority)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 2),
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
              color: widget.item.isPriority ? colorScheme.primary : null,
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
            index: widget.index,
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

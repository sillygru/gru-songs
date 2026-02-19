import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/queue_item.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio_player_manager.dart';
import '../widgets/album_art_image.dart' show StaticAlbumArtImage;
import '../widgets/audio_visualizer.dart';

class NextUpScreen extends ConsumerStatefulWidget {
  const NextUpScreen({super.key});

  @override
  ConsumerState<NextUpScreen> createState() => _NextUpScreenState();
}

class _NextUpScreenState extends ConsumerState<NextUpScreen> {
  _PendingRemoval? _pendingRemoval;
  Timer? _undoTimer;
  final Set<String> _locallyDismissedQueueIds = <String>{};

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  Future<void> _removeWithUndo({
    required AudioPlayerManager audioManager,
    required QueueItem item,
    required int absoluteIndex,
  }) async {
    try {
      await audioManager.removeFromQueue(absoluteIndex);
    } catch (_) {
      if (mounted) {
        setState(() {
          _locallyDismissedQueueIds.remove(item.queueId);
        });
      }
      return;
    }
    _undoTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _pendingRemoval =
          _PendingRemoval(item: item, absoluteIndex: absoluteIndex);
    });

    _undoTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _pendingRemoval = null);
    });
  }

  Future<void> _undoRemoval(AudioPlayerManager audioManager) async {
    final pending = _pendingRemoval;
    if (pending == null) return;

    final currentLength = audioManager.queueNotifier.value.length;
    final insertIndex = pending.absoluteIndex.clamp(0, currentLength);
    await audioManager.insertIntoQueue(insertIndex, pending.item);

    _undoTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _pendingRemoval = null;
      _locallyDismissedQueueIds.remove(pending.item.queueId);
    });
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

  void _onCurrentWaveTap(AudioPlayerManager audioManager) {
    HapticFeedback.selectionClick();
    if (audioManager.player.playing) {
      unawaited(audioManager.player.pause());
      return;
    }
    unawaited(audioManager.player.play());
  }

  void _onQueueRowTap({
    required AudioPlayerManager audioManager,
    required int currentIndex,
    required int tappedIndex,
  }) {
    if ((tappedIndex - currentIndex).abs() != 1) return;
    HapticFeedback.selectionClick();
    unawaited(() async {
      await audioManager.player.seek(Duration.zero, index: tappedIndex);
      await audioManager.player.play();
    }());
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = ref.read(audioPlayerManagerProvider);
    final extractedColor = ref.watch(themeProvider).extractedColor;
    final settings = ref.watch(settingsProvider);
    final useAnimatedWave = settings.animatedSoundWaveEnabled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Next Up',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Shuffle Remaining',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              audioManager.refreshQueue();
            },
          ),
          IconButton(
            tooltip: 'Clear All',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _showClearConfirm(context, audioManager),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _BackdropLayer(),
          SafeArea(
            top: false,
            child: ValueListenableBuilder<List<QueueItem>>(
              valueListenable: audioManager.queueNotifier,
              builder: (context, queue, child) {
                return StreamBuilder<int?>(
                  stream: audioManager.player.currentIndexStream,
                  initialData: audioManager.player.currentIndex,
                  builder: (context, snapshot) {
                    final currentIndex = snapshot.data ?? -1;
                    final playedQueue = currentIndex > 0
                        ? queue.take(currentIndex).toList()
                        : <QueueItem>[];
                    final currentItem =
                        currentIndex >= 0 && currentIndex < queue.length
                            ? queue[currentIndex]
                            : null;
                    final upcomingQueue = currentIndex >= 0
                        ? queue.skip(currentIndex + 1).toList()
                        : queue;
                    final visibleUpcomingQueue = upcomingQueue
                        .where((item) =>
                            !_locallyDismissedQueueIds.contains(item.queueId))
                        .toList();

                    return CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        if (playedQueue.isNotEmpty)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                return Opacity(
                                  opacity: 0.42,
                                  child: _QueueRow(
                                    item: playedQueue[index],
                                    isCurrent: false,
                                    onTap: () => _onQueueRowTap(
                                      audioManager: audioManager,
                                      currentIndex: currentIndex,
                                      tappedIndex: index,
                                    ),
                                  ),
                                );
                              },
                              childCount: playedQueue.length,
                            ),
                          ),
                        if (currentItem != null)
                          SliverToBoxAdapter(
                            child: StreamBuilder<PlayerState>(
                              stream: audioManager.player.playerStateStream,
                              initialData: audioManager.player.playerState,
                              builder: (context, snapshot) {
                                final isPlaying =
                                    snapshot.data?.playing ?? false;
                                return _QueueRow(
                                  item: currentItem,
                                  isCurrent: true,
                                  currentAccent: extractedColor,
                                  showAnimatedWave:
                                      useAnimatedWave && isPlaying,
                                  onCurrentIndicatorTap: () =>
                                      _onCurrentWaveTap(audioManager),
                                );
                              },
                            ),
                          ),
                        if (visibleUpcomingQueue.isNotEmpty)
                          SliverReorderableList(
                            itemCount: visibleUpcomingQueue.length,
                            onReorder: (oldIndex, newIndex) {
                              HapticFeedback.selectionClick();
                              final oldItem = visibleUpcomingQueue[oldIndex];
                              final oldAbsoluteIndex = queue.indexWhere(
                                  (queued) =>
                                      queued.queueId == oldItem.queueId);
                              if (oldAbsoluteIndex == -1) return;

                              int adjustedNewIndex = newIndex;
                              if (oldIndex < adjustedNewIndex) {
                                adjustedNewIndex -= 1;
                              }
                              final withoutOld =
                                  List<QueueItem>.from(visibleUpcomingQueue)
                                    ..removeAt(oldIndex);

                              int targetAbsoluteIndex;
                              if (adjustedNewIndex >= withoutOld.length) {
                                targetAbsoluteIndex = queue.length;
                              } else {
                                final targetItem = withoutOld[adjustedNewIndex];
                                targetAbsoluteIndex = queue.indexWhere(
                                    (queued) =>
                                        queued.queueId == targetItem.queueId);
                                if (targetAbsoluteIndex == -1) return;
                              }

                              audioManager.reorderQueue(
                                oldAbsoluteIndex,
                                targetAbsoluteIndex,
                              );
                            },
                            itemBuilder: (context, index) {
                              final item = visibleUpcomingQueue[index];
                              final absoluteIndex = queue.indexWhere(
                                  (queued) => queued.queueId == item.queueId);
                              if (absoluteIndex == -1) {
                                return const SizedBox.shrink();
                              }

                              return Dismissible(
                                key: ValueKey('dismiss_${item.queueId}'),
                                direction: DismissDirection.horizontal,
                                movementDuration:
                                    const Duration(milliseconds: 170),
                                resizeDuration:
                                    const Duration(milliseconds: 130),
                                dismissThresholds: const {
                                  DismissDirection.startToEnd: 0.25,
                                  DismissDirection.endToStart: 0.25,
                                },
                                background:
                                    Container(color: Colors.transparent),
                                secondaryBackground:
                                    Container(color: Colors.transparent),
                                onDismissed: (_) {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    _locallyDismissedQueueIds.add(item.queueId);
                                  });
                                  _removeWithUndo(
                                    audioManager: audioManager,
                                    item: item,
                                    absoluteIndex: absoluteIndex,
                                  );
                                },
                                child: _QueueRow(
                                  key: ValueKey(item.queueId),
                                  item: item,
                                  isCurrent: false,
                                  showActions: true,
                                  onTap: () => _onQueueRowTap(
                                    audioManager: audioManager,
                                    currentIndex: currentIndex,
                                    tappedIndex: absoluteIndex,
                                  ),
                                  onTogglePriority: () {
                                    HapticFeedback.mediumImpact();
                                    audioManager.togglePriority(absoluteIndex);
                                  },
                                  onRemove: () {
                                    HapticFeedback.mediumImpact();
                                    _removeWithUndo(
                                      audioManager: audioManager,
                                      item: item,
                                      absoluteIndex: absoluteIndex,
                                    );
                                  },
                                  dragHandle: ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(Icons.drag_indicator_rounded,
                                          size: 20),
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyUpcoming(),
                          ),
                        const SliverPadding(
                            padding: EdgeInsets.only(bottom: 90)),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 28,
            child: SafeArea(
              bottom: true,
              minimum: const EdgeInsets.only(bottom: 12),
              child: IgnorePointer(
                ignoring: _pendingRemoval == null,
                child: AnimatedOpacity(
                  opacity: _pendingRemoval == null ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: _UndoBar(
                    onUndo: () => _undoRemoval(audioManager),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropLayer extends StatelessWidget {
  const _BackdropLayer();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.blueGrey.shade900.withValues(alpha: 0.86),
            Colors.black.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(color: Colors.black.withValues(alpha: 0.2)),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final QueueItem item;
  final bool isCurrent;
  final bool showActions;
  final bool showAnimatedWave;
  final Color? currentAccent;
  final VoidCallback? onTogglePriority;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final VoidCallback? onCurrentIndicatorTap;
  final Widget? dragHandle;

  const _QueueRow({
    super.key,
    required this.item,
    required this.isCurrent,
    this.showActions = false,
    this.showAnimatedWave = false,
    this.currentAccent,
    this.onTogglePriority,
    this.onRemove,
    this.onTap,
    this.onCurrentIndicatorTap,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final song = item.song;
    final colorScheme = Theme.of(context).colorScheme;

    final cardColor = isCurrent
        ? (currentAccent ?? colorScheme.primary).withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.07);

    return _GlassPanel(
      color: cardColor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              const SizedBox(width: 10),
              StaticAlbumArtImage(
                url: song.coverUrl ?? '',
                filename: song.filename,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCurrentIndicatorTap,
                    child: showAnimatedWave
                        ? const AudioVisualizer(
                            width: 16,
                            height: 16,
                            color: Colors.white,
                            isPlaying: true,
                          )
                        : const Icon(Icons.graphic_eq_rounded, size: 18),
                  ),
                ),
              if (showActions) ...[
                IconButton(
                  icon: Icon(
                    item.isPriority
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 18,
                    color: item.isPriority ? colorScheme.primary : null,
                  ),
                  tooltip: item.isPriority ? 'Unpin' : 'Pin to Top',
                  onPressed: onTogglePriority,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
                if (dragHandle != null) dragHandle!,
              ] else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _UndoBar extends StatelessWidget {
  final VoidCallback onUndo;

  const _UndoBar({required this.onUndo});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Removed from queue',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: onUndo,
                child: const Text(
                  'Undo?',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyUpcoming extends StatelessWidget {
  const _EmptyUpcoming();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Nothing\'s next',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final Color color;

  const _GlassPanel({
    required this.child,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(color: color),
          child: child,
        ),
      ),
    );
  }
}

class _PendingRemoval {
  final QueueItem item;
  final int absoluteIndex;

  const _PendingRemoval({
    required this.item,
    required this.absoluteIndex,
  });
}

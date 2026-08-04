import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../models/queue_item.dart';
import '../../../models/queue_snapshot.dart';
import '../../../models/song.dart';
import '../../../providers/providers.dart';
import '../../../providers/queue_history_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/audio_player_manager.dart';
import '../../components/player_glass_surface.dart';
import '../../components/player_section_header.dart';
import '../../components/player_segmented_pill.dart';
import '../../components/player_track_row.dart';
import '../../components/queue_cover_mosaic.dart';
import '../../tokens/player_tokens.dart';
import '../../widgets/duration_display.dart' show DurationFormatter;

/// Right pane: the live queue, plus past queue snapshots. Content only — the
/// shell owns the backdrop, header, pill and transport dock. Do not add a
/// Scaffold, AppBar or background here.
class QueuePane extends ConsumerStatefulWidget {
  final Color accent;
  final bool initialShowHistory;

  const QueuePane({
    super.key,
    required this.accent,
    this.initialShowHistory = false,
  });

  @override
  ConsumerState<QueuePane> createState() => _QueuePaneState();
}

class _QueuePaneState extends ConsumerState<QueuePane>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final ValueNotifier<double> _segment;
  late bool _showHistory;

  /// 1 = chrome (segment pill + summary row) shown, 0 = collapsed. Driven by
  /// scroll direction rather than offset, so a small scroll back up brings it
  /// straight back instead of only at the very top of the list.
  late final AnimationController _chrome;
  late final Animation<double> _chromeCurve;

  /// A scroll direction must persist this long before the chrome reacts. A
  /// finger held still keeps firing idle-flicks in both directions, and the
  /// pending action gets cancelled each time — so jitter can't flip the chrome,
  /// only a sustained scroll moves it.
  static const Duration _chromeSettleDelay = Duration(milliseconds: 120);

  Timer? _chromeSettleTimer;

  /// Queue ids swiped to the top this session, most recent last. RAM only —
  /// the manager reads it to stack rapid swipes above each other, and it dies
  /// with this pane, which is exactly the "temporarily" asked for.
  final List<String> _addedToTop = <String>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _showHistory = widget.initialShowHistory;
    _segment = ValueNotifier(_showHistory ? 1 : 0);
    _chrome = AnimationController(
      vsync: this,
      duration: PlayerTokens.dFast,
      value: 1,
    );
    _chromeCurve = CurvedAnimation(
      parent: _chrome,
      curve: PlayerTokens.cStandard,
    );
  }

  @override
  void dispose() {
    _cancelChromeSettle();
    _segment.dispose();
    _chrome.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _showHistory = index == 1);
    _segment.value = index.toDouble();
    _chrome.forward();
  }

  void _cancelChromeSettle() {
    _chromeSettleTimer?.cancel();
    _chromeSettleTimer = null;
  }

  void _scheduleChromeAction(VoidCallback action) {
    _chromeSettleTimer?.cancel();
    _chromeSettleTimer = Timer(_chromeSettleDelay, () {
      _chromeSettleTimer = null;
      action();
    });
  }

  /// Notifications bubble up from whichever list is currently showing, so one
  /// listener here covers both segments.
  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    // The one preference governs the app bars and this chrome: with auto-hide
    // off the chrome stays put, so nothing here may touch it.
    if (!ref.read(settingsProvider).autoHideBottomBarOnScroll) {
      _cancelChromeSettle();
      if (_chrome.value < 1) _chrome.forward();
      return false;
    }

    switch (notification.direction) {
      case ScrollDirection.reverse:
        // Nothing to hide for a list that doesn't actually scroll.
        if (notification.metrics.maxScrollExtent > 0) {
          _scheduleChromeAction(() => _chrome.reverse());
        } else {
          _cancelChromeSettle();
        }
      case ScrollDirection.forward:
        _scheduleChromeAction(() => _chrome.forward());
      case ScrollDirection.idle:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // If auto-hide is switched off while this pane is alive, whatever is
    // hidden comes straight back — the setting wins over the current state.
    ref.listen(
      settingsProvider.select((s) => s.autoHideBottomBarOnScroll),
      (_, autoHide) {
        if (!autoHide && _chrome.value < 1) {
          _cancelChromeSettle();
          _chrome.forward();
        }
      },
    );

    return Column(
      children: [
        _CollapsibleChrome(
          animation: _chromeCurve,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PlayerTokens.s6,
              PlayerTokens.s2,
              PlayerTokens.s6,
              PlayerTokens.s2,
            ),
            child: PlayerSegmentedPill(
              labels: const ['Up Next', 'History'],
              position: _segment,
              onSelected: _select,
              accent: widget.accent,
              compact: true,
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onUserScroll,
            child: AnimatedSwitcher(
              duration: PlayerTokens.dFast,
              child: _showHistory
                  ? _HistoryList(
                      key: const ValueKey('history'), accent: widget.accent)
                  : _UpNextList(
                      key: const ValueKey('upnext'),
                      accent: widget.accent,
                      chrome: _chromeCurve,
                      addedToTop: _addedToTop,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Collapses its child upward — height and opacity together — so the queue
/// chrome gets out of the way while scrolling without leaving a gap behind.
class _CollapsibleChrome extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _CollapsibleChrome({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Up Next
// ---------------------------------------------------------------------------

class _UpNextList extends ConsumerStatefulWidget {
  final Color accent;

  /// The pane's collapse animation — the summary row rides it so it hides in
  /// step with the segment pill.
  final Animation<double> chrome;

  /// Queue ids swiped to the top this session, most recent last. Owned by the
  /// pane so it survives segment switches, and passed down so the manager can
  /// stack each new swipe after the previous one.
  final List<String> addedToTop;

  const _UpNextList({
    super.key,
    required this.accent,
    required this.chrome,
    required this.addedToTop,
  });

  @override
  ConsumerState<_UpNextList> createState() => _UpNextListState();
}

class _UpNextListState extends ConsumerState<_UpNextList> {
  /// Rough height of the 'Played' section header, used only to get the current
  /// row built before [_snapCurrentToTop] measures it exactly.
  static const double _sectionHeaderHeight = 40;

  final ScrollController _scrollController = ScrollController();

  /// Marks the current track's row so it can be measured rather than estimated.
  final GlobalKey _currentRowKey = GlobalKey();

  /// Queue ids dismissed locally, so a swiped row disappears immediately
  /// instead of flickering until the manager's notifier catches up.
  final Set<String> _dismissed = <String>{};

  _PendingRemoval? _pendingRemoval;
  Timer? _undoTimer;
  bool _didAutoScroll = false;

  @override
  void dispose() {
    _undoTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Opens the list on the current track, pinned to the top, so what's coming
  /// up is what you see first — played rows stay one scroll up.
  void _autoScrollToCurrent(int currentIndex) {
    if (_didAutoScroll || currentIndex < 0) return;
    _didAutoScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // Estimate first: rows below the fold are never built, so the current
      // row has no context to measure until something near it is on screen.
      final estimate = currentIndex == 0
          ? 0.0
          : _sectionHeaderHeight + currentIndex * PlayerTokens.rowHeight;
      _scrollController.jumpTo(
        estimate.clamp(0.0, _scrollController.position.maxScrollExtent),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) => _snapCurrentToTop());
    });
  }

  /// Corrects the estimate once the row is real — row heights are uniform but
  /// the section headers and paddings around them are not.
  void _snapCurrentToTop() {
    if (!mounted || !_scrollController.hasClients) return;

    final box = _currentRowKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box == null || viewport == null) return;

    final position = _scrollController.position;
    final target = viewport
        .getOffsetToReveal(box, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.jumpTo(target);
  }

  Future<void> _remove(
    AudioPlayerManager audioManager,
    QueueItem item,
    int absoluteIndex,
  ) async {
    setState(() => _dismissed.add(item.queueId));

    try {
      await audioManager.removeFromQueue(absoluteIndex);
    } catch (_) {
      // Rare failure path — same Dismissible hazard as _addToTop: the row must
      // actually leave the tree before it can come back.
      _restoreRow(item.queueId);
      return;
    }

    _undoTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _pendingRemoval = _PendingRemoval(item: item, index: absoluteIndex);
    });
    _undoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pendingRemoval = null);
    });
  }

  /// The left-to-right swipe: push the entry to the top of the upcoming
  /// section, remembering it in [widget.addedToTop] so the next swipe lands
  /// just after it. Nothing leaves the queue, so nothing needs an undo path —
  /// the reorder itself is the reversible action.
  Future<void> _addToTop(
    AudioPlayerManager audioManager,
    QueueItem item,
    List<QueueItem> queue,
  ) async {
    final absolute =
        queue.indexWhere((queued) => queued.queueId == item.queueId);
    if (absolute == -1) return;

    // The Dismissible must leave the tree the moment onDismissed fires — it
    // asserts if it survives its resize animation. Hide the row exactly like
    // _remove does, then bring it back once the move has actually landed.
    setState(() => _dismissed.add(item.queueId));

    final topOrder = List<String>.of(widget.addedToTop)..add(item.queueId);
    var moved = false;
    try {
      await audioManager.moveUpcomingToTop(item.queueId, topOrder);
      moved = true;
    } catch (_) {
      // The move failed, so the row simply stays where it is.
    }

    if (!mounted) return;
    if (moved) {
      setState(() => widget.addedToTop
        ..remove(item.queueId)
        ..add(item.queueId));
    }
    _restoreRow(item.queueId);
  }

  /// Brings a hidden row back after the next frame. The manager's mutation can
  /// resolve within the same microtask turn as [Dismissible.onDismissed], so
  /// restoring in that turn rebuilds the row before its resize animation ever
  /// saw it leave the tree — which trips the "dismissed Dismissible is still
  /// part of the tree" assert. Waiting one frame guarantees the unmount.
  void _restoreRow(String queueId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dismissed.contains(queueId)) return;
      setState(() => _dismissed.remove(queueId));
    });
  }

  Future<void> _undo(AudioPlayerManager audioManager) async {
    final pending = _pendingRemoval;
    if (pending == null) return;

    final length = audioManager.queueNotifier.value.length;
    await audioManager.insertIntoQueue(
      pending.index.clamp(0, length),
      pending.item,
    );

    _undoTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _dismissed.remove(pending.item.queueId);
      _pendingRemoval = null;
    });
  }

  void _confirmClear(AudioPlayerManager audioManager) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Queue?'),
        content: const Text(
          'This will remove all upcoming songs from the current queue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              audioManager.clearUpcoming();
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final animatedWave =
        ref.watch(settingsProvider.select((s) => s.animatedSoundWaveEnabled));
    final visualizerMode =
        ref.watch(settingsProvider.select((s) => s.visualizerMode));

    return ValueListenableBuilder<List<QueueItem>>(
      valueListenable: audioManager.queueNotifier,
      builder: (context, queue, _) {
        return StreamBuilder<int?>(
          stream: audioManager.player.currentIndexStream,
          initialData: audioManager.player.currentIndex,
          builder: (context, snapshot) {
            final currentIndex = snapshot.data ?? -1;
            _autoScrollToCurrent(currentIndex);

            final played = currentIndex > 0
                ? queue.take(currentIndex).toList()
                : <QueueItem>[];
            final current = currentIndex >= 0 && currentIndex < queue.length
                ? queue[currentIndex]
                : null;
            final upcoming =
                (currentIndex >= 0 ? queue.skip(currentIndex + 1) : queue)
                    .where((item) => !_dismissed.contains(item.queueId))
                    .toList();

            if (queue.isEmpty) return _buildEmptyState(context);

            return Column(
              children: [
                _CollapsibleChrome(
                  animation: widget.chrome,
                  child: _buildSummary(context, upcoming, audioManager),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      CustomScrollView(
                        controller: _scrollController,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          if (played.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: const PlayerSectionHeader(label: 'Played'),
                            ),
                            SliverList.builder(
                              itemCount: played.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PlayerTokens.s3,
                                ),
                                child: PlayerTrackRow(
                                  song: played[index].song,
                                  accent: widget.accent,
                                  isPlayed: true,
                                  onTap: () =>
                                      _jumpTo(audioManager, played[index]),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: const PlayerSectionHeader(
                                  label: 'Now playing'),
                            ),
                          ],
                          if (current != null)
                            SliverToBoxAdapter(
                              child: StreamBuilder<PlayerState>(
                                stream: audioManager.player.playerStateStream,
                                initialData: audioManager.player.playerState,
                                builder: (context, stateSnapshot) {
                                  final playing =
                                      stateSnapshot.data?.playing ?? false;
                                  return Padding(
                                    key: _currentRowKey,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: PlayerTokens.s3,
                                      vertical: PlayerTokens.s1,
                                    ),
                                    child: PlayerTrackRow(
                                      song: current.song,
                                      accent: widget.accent,
                                      isCurrent: true,
                                      showAnimatedWave: animatedWave &&
                                          playing &&
                                          visualizerMode != VisualizerMode.off,
                                      visualizerMode: visualizerMode,
                                      onIndicatorTap: () {
                                        HapticFeedback.selectionClick();
                                        audioManager.togglePlayPause();
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (upcoming.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child:
                                  const PlayerSectionHeader(label: 'Up next'),
                            ),
                            SliverReorderableList(
                              itemCount: upcoming.length,
                              onReorderItem: (oldIndex, newIndex) => _reorder(
                                audioManager,
                                queue,
                                upcoming,
                                oldIndex,
                                newIndex,
                              ),
                              itemBuilder: (context, index) {
                                final item = upcoming[index];
                                return _buildUpcomingRow(
                                  context,
                                  audioManager,
                                  queue,
                                  item,
                                  index,
                                );
                              },
                            ),
                          ],
                          const SliverToBoxAdapter(
                            child: SizedBox(height: PlayerTokens.s6),
                          ),
                        ],
                      ),
                      if (_pendingRemoval != null)
                        Positioned(
                          left: PlayerTokens.s4,
                          right: PlayerTokens.s4,
                          bottom: PlayerTokens.s4,
                          child: _UndoBar(
                            title: _pendingRemoval!.item.song.title,
                            accent: widget.accent,
                            onUndo: () => _undo(audioManager),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUpcomingRow(
    BuildContext context,
    AudioPlayerManager audioManager,
    List<QueueItem> queue,
    QueueItem item,
    int index,
  ) {
    return Dismissible(
      key: ValueKey('upnext_${item.queueId}'),
      direction: DismissDirection.horizontal,
      background: _buildSwipeBackground(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: PlayerTokens.s4),
        message: 'Add to top',
        icon: Icons.vertical_align_top_rounded,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
      secondaryBackground: _buildSwipeBackground(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: PlayerTokens.s4),
        message: 'Remove',
        color: Colors.redAccent,
        icon: Icons.delete_outline_rounded,
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          _addToTop(audioManager, item, queue);
        } else {
          final absolute =
              queue.indexWhere((queued) => queued.queueId == item.queueId);
          if (absolute == -1) return;
          _remove(audioManager, item, absolute);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PlayerTokens.s3),
        child: PlayerTrackRow(
          song: item.song,
          accent: widget.accent,
          onTap: () => _jumpTo(audioManager, item),
          trailing: ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle_rounded,
              color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
            ),
          ),
        ),
      ),
    );
  }

  /// Shared background for the swipe affordance: a full-height tinted slab with
  /// the label and icon anchored to the side the finger is heading towards.
  Widget _buildSwipeBackground({
    required Alignment alignment,
    required EdgeInsets padding,
    required String message,
    required IconData icon,
    Color? color,
  }) {
    return Container(
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: PlayerTokens.brMd,
        color: color ?? Colors.white.withValues(alpha: 0.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: PlayerTokens.s1),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// The visible list is a filtered slice of the real queue, so indices must be
  /// mapped back through queueId before touching the manager — passing the
  /// visible index straight through would reorder the wrong track.
  void _reorder(
    AudioPlayerManager audioManager,
    List<QueueItem> queue,
    List<QueueItem> upcoming,
    int oldIndex,
    int newIndex,
  ) {
    HapticFeedback.selectionClick();

    final moved = upcoming[oldIndex];
    final fromAbsolute =
        queue.indexWhere((queued) => queued.queueId == moved.queueId);
    if (fromAbsolute == -1) return;

    // onReorderItem reports the item's *final* index, while reorderQueue speaks
    // the insertion-slot convention (it subtracts one itself when moving down).
    // Convert back to a slot before translating visible -> absolute.
    final slot = newIndex > oldIndex ? newIndex + 1 : newIndex;

    final int toAbsolute;
    if (slot < upcoming.length) {
      // Land immediately in front of whatever the item was dropped above.
      toAbsolute = queue.indexWhere(
        (queued) => queued.queueId == upcoming[slot].queueId,
      );
    } else {
      final lastAbsolute = queue.indexWhere(
        (queued) => queued.queueId == upcoming.last.queueId,
      );
      toAbsolute = lastAbsolute < 0 ? -1 : lastAbsolute + 1;
    }

    if (toAbsolute < 0) return;
    audioManager.reorderQueue(fromAbsolute, toAbsolute);
  }

  /// Tapping any row plays it next and skips onto it — the manager decides
  /// whether that means moving an upcoming entry up or copying a played one,
  /// so nothing before the current track is ever disturbed.
  void _jumpTo(AudioPlayerManager audioManager, QueueItem item) {
    HapticFeedback.selectionClick();
    unawaited(audioManager.jumpToQueueItem(item.queueId));
  }

  Widget _buildSummary(
    BuildContext context,
    List<QueueItem> upcoming,
    AudioPlayerManager audioManager,
  ) {
    final seconds = upcoming.fold<int>(
      0,
      (total, item) => total + (item.song.duration?.inSeconds ?? 0),
    );
    final remaining = DurationFormatter.formatRemaining(seconds);
    final count = upcoming.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s5,
        PlayerTokens.s2,
        PlayerTokens.s3,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$count ${count == 1 ? 'song' : 'songs'}',
                    style: PlayerTokens.trackSubtitle(context)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (remaining.isNotEmpty)
                    TextSpan(
                      text: '  ·  $remaining',
                      style: PlayerTokens.meta(context),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Shuffle upcoming',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.shuffle_rounded, size: 20),
            color: Colors.white.withValues(alpha: PlayerTokens.aSecondary),
            onPressed: () {
              HapticFeedback.selectionClick();
              // A one-off reshuffle of what is already queued — this does not
              // touch the shuffle/ordered mode, which lives on the player pane.
              audioManager.shuffleUpcoming();
            },
          ),
          IconButton(
            tooltip: 'Clear upcoming',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
            color: Colors.white.withValues(alpha: PlayerTokens.aSecondary),
            onPressed: () => _confirmClear(audioManager),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 44,
            color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
          ),
          const SizedBox(height: PlayerTokens.s3),
          Text('Queue is empty', style: PlayerTokens.paneTitle(context)),
        ],
      ),
    );
  }
}

class _PendingRemoval {
  final QueueItem item;
  final int index;

  const _PendingRemoval({required this.item, required this.index});
}

class _UndoBar extends StatelessWidget {
  final String title;
  final Color accent;
  final VoidCallback onUndo;

  const _UndoBar({
    required this.title,
    required this.accent,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    // The one remaining glass surface: it floats over the scrolling list, so it
    // needs its own backing to stay readable. Borderless to match the rest.
    return PlayerGlassSurface(
      strong: true,
      bordered: false,
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s4,
        PlayerTokens.s2,
        PlayerTokens.s2,
        PlayerTokens.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Removed $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PlayerTokens.trackSubtitle(context),
            ),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class _HistoryList extends ConsumerStatefulWidget {
  final Color accent;

  const _HistoryList({super.key, required this.accent});

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList> {
  String? _expandedId;

  void _confirmClearAll() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text('This will delete every saved queue snapshot.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(queueHistoryProvider.notifier).clearAll();
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(QueueSnapshot snapshot) async {
    final songs = await ref.read(
      queueSnapshotSongsProvider(snapshot.id).future,
    );
    if (songs.isEmpty || !mounted) return;

    await ref.read(audioPlayerManagerProvider).replaceQueue(
          songs,
          playlistId: snapshot.id,
          forceLinear: true,
          clearCurrentSong: true,
          saveSnapshot: false,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored ${songs.length} tracks')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(queueHistoryProvider);

    return history.when(
      loading: () => const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
      error: (error, _) => Center(
        child:
            Text('Could not load history', style: PlayerTokens.meta(context)),
      ),
      data: (snapshots) {
        if (snapshots.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 44,
                  color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
                ),
                const SizedBox(height: PlayerTokens.s3),
                Text('No past queues', style: PlayerTokens.paneTitle(context)),
                const SizedBox(height: PlayerTokens.s1),
                Text(
                  'Queues you play get saved here automatically.',
                  style: PlayerTokens.meta(context),
                ),
              ],
            ),
          );
        }

        // Snapshots come back newest-first, so walking them in order and
        // emitting a header whenever the day bucket changes is enough to group
        // them — no sorting or second pass needed.
        final rows = <Object>[
          _HistoryHeader(
            label: '${snapshots.length} saved queues',
            onClearAll: _confirmClearAll,
          ),
        ];
        String? bucket;
        for (final snapshot in snapshots) {
          final label = _dayBucket(snapshot.createdDateTime);
          if (label != bucket) {
            bucket = label;
            rows.add(label);
          }
          rows.add(snapshot);
        }

        return ListView.builder(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: PlayerTokens.s6),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];

            if (row is _HistoryHeader) {
              return PlayerSectionHeader(
                label: row.label,
                trailingLabel: 'Clear all',
                trailingIcon: Icons.delete_sweep_rounded,
                onTrailingTap: row.onClearAll,
              );
            }
            if (row is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  PlayerTokens.s5,
                  PlayerTokens.s3,
                  PlayerTokens.s5,
                  PlayerTokens.s1,
                ),
                child: Text(row, style: PlayerTokens.sectionLabel(context)),
              );
            }

            final snapshot = row as QueueSnapshot;
            return _SnapshotCard(
              snapshot: snapshot,
              accent: widget.accent,
              expanded: _expandedId == snapshot.id,
              onToggle: () => setState(
                () => _expandedId =
                    _expandedId == snapshot.id ? null : snapshot.id,
              ),
              onRestore: () => _restore(snapshot),
              onDelete: () => ref
                  .read(queueHistoryProvider.notifier)
                  .deleteSnapshot(snapshot.id),
            );
          },
        );
      },
    );
  }

  static String _dayBucket(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final diff = today.difference(day).inDays;

    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    if (diff < 30) return 'This month';
    return 'Earlier';
  }
}

class _HistoryHeader {
  final String label;
  final VoidCallback onClearAll;

  const _HistoryHeader({required this.label, required this.onClearAll});
}

/// One saved queue. The mosaic on the left is what makes a snapshot
/// identifiable — the stored name is a timestamp, which reads as noise in a
/// list, so covers, source and length do the recognising instead.
class _SnapshotCard extends ConsumerWidget {
  final QueueSnapshot snapshot;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _SnapshotCard({
    required this.snapshot,
    required this.accent,
    required this.expanded,
    required this.onToggle,
    required this.onRestore,
    required this.onDelete,
  });

  /// How many rows an expanded snapshot lists before it stops. A shuffle of the
  /// whole library can be hundreds of tracks, and this card lives inside
  /// another list, so it must not build all of them.
  static const int _maxExpandedRows = 25;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolved straight from the loaded library rather than the database: the
    // snapshot already carries its filenames, so a history list of twenty cards
    // costs one shared map instead of twenty queries.
    final byFilename = ref.watch(songsByFilenameProvider);
    final tracks = snapshot.songFilenames
        .map((filename) => byFilename[filename])
        .whereType<Song>()
        .toList();

    final playlistName = ref.watch(
      userDataProvider.select((state) {
        for (final playlist in state.playlists) {
          if (playlist.id == snapshot.source) return playlist.name;
        }
        return null;
      }),
    );

    final missing = snapshot.songFilenames.length - tracks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s3,
        PlayerTokens.s1,
        PlayerTokens.s3,
        PlayerTokens.s1,
      ),
      // Flat row on the backdrop rather than a card — a list of stacked
      // bordered boxes is exactly the look being avoided here. Expanding tints
      // the whole block instead of outlining it.
      child: AnimatedContainer(
        duration: PlayerTokens.dFast,
        curve: PlayerTokens.cStandard,
        decoration: BoxDecoration(
          color: expanded
              ? accent.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: PlayerTokens.brMd,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(context, tracks, playlistName),
            AnimatedSize(
              duration: PlayerTokens.dBase,
              curve: PlayerTokens.cStandard,
              alignment: Alignment.topCenter,
              child: expanded
                  ? _buildTracks(context, tracks, missing)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<Song> tracks,
    String? playlistName,
  ) {
    final fromShuffle = snapshot.source == 'shuffle';
    final total = DurationFormatter.formatTotalCompact(tracks);
    final count = snapshot.songFilenames.length;
    final meta = [
      '$count ${count == 1 ? 'track' : 'tracks'}',
      if (total.isNotEmpty) total,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(PlayerTokens.s3),
          child: Row(
            children: [
              QueueCoverMosaic(
                songs: tracks,
                accent: accent,
                seed: snapshot.id,
              ),
              const SizedBox(width: PlayerTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title(playlistName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PlayerTokens.trackTitle(context)
                          .copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          fromShuffle
                              ? Icons.shuffle_rounded
                              : Icons.queue_music_rounded,
                          size: 12,
                          color: Colors.white
                              .withValues(alpha: PlayerTokens.aTertiary),
                        ),
                        const SizedBox(width: PlayerTokens.s1),
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PlayerTokens.trackSubtitle(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.displayDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PlayerTokens.meta(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PlayerTokens.s2),
              _PlayChip(accent: accent, onTap: onRestore),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: PlayerTokens.dFast,
                curve: PlayerTokens.cStandard,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: PlayerTokens.aTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stored names are timestamps unless the user renamed the snapshot, so a
  /// custom name wins, then the playlist it came from, then the source.
  String _title(String? playlistName) {
    final isDefaultName = snapshot.name ==
        QueueSnapshot.defaultNameForTimestamp(snapshot.createdAt);
    if (!isDefaultName && snapshot.name.trim().isNotEmpty) return snapshot.name;
    if (playlistName != null && playlistName.trim().isNotEmpty) {
      return playlistName;
    }
    return snapshot.source == 'shuffle' ? 'Shuffled queue' : 'Saved queue';
  }

  Widget _buildTracks(BuildContext context, List<Song> tracks, int missing) {
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          PlayerTokens.s4,
          0,
          PlayerTokens.s4,
          PlayerTokens.s4,
        ),
        child: Text(
          'None of these tracks are still in your library.',
          style: PlayerTokens.meta(context),
        ),
      );
    }

    final shown = tracks.take(_maxExpandedRows).toList();
    final hidden = tracks.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        for (var i = 0; i < shown.length; i++)
          PlayerTrackRow(
            song: shown[i],
            accent: accent,
            index: i,
            onTap: onRestore,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PlayerTokens.s4,
            PlayerTokens.s1,
            PlayerTokens.s2,
            PlayerTokens.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (hidden > 0) '+$hidden more',
                    if (missing > 0) '$missing missing from library',
                  ].join(' · '),
                  style: PlayerTokens.meta(context),
                ),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent.withValues(alpha: 0.9),
                  textStyle: PlayerTokens.meta(context)
                      .copyWith(fontWeight: FontWeight.w700),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PlayerTokens.s3,
                    vertical: PlayerTokens.s1,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Filled accent circle that restores a snapshot. Reads as the one primary
/// action on the card, so the row doesn't need a second icon button competing
/// with it.
class _PlayChip extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _PlayChip({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.play_arrow_rounded, size: 22, color: accent),
        ),
      ),
    );
  }
}

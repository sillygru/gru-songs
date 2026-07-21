import 'dart:async';

import 'package:flutter/material.dart';
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
    with AutomaticKeepAliveClientMixin {
  late final ValueNotifier<double> _segment;
  late bool _showHistory;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _showHistory = widget.initialShowHistory;
    _segment = ValueNotifier(_showHistory ? 1 : 0);
  }

  @override
  void dispose() {
    _segment.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _showHistory = index == 1);
    _segment.value = index.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Padding(
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
        Expanded(
          child: AnimatedSwitcher(
            duration: PlayerTokens.dFast,
            child: _showHistory
                ? _HistoryList(
                    key: const ValueKey('history'), accent: widget.accent)
                : _UpNextList(
                    key: const ValueKey('upnext'), accent: widget.accent),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Up Next
// ---------------------------------------------------------------------------

class _UpNextList extends ConsumerStatefulWidget {
  final Color accent;

  const _UpNextList({super.key, required this.accent});

  @override
  ConsumerState<_UpNextList> createState() => _UpNextListState();
}

class _UpNextListState extends ConsumerState<_UpNextList> {
  final ScrollController _scrollController = ScrollController();

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

  void _autoScrollToCurrent(int currentIndex) {
    if (_didAutoScroll || currentIndex < 0) return;
    _didAutoScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      // Leave a few played rows visible above the current track for context.
      const rowsAbove = 3;
      final target = ((currentIndex - rowsAbove).clamp(0, currentIndex)) *
          PlayerTokens.rowHeight;
      _scrollController.jumpTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
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
      if (mounted) setState(() => _dismissed.remove(item.queueId));
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

            return Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildSummary(context, upcoming, audioManager),
                    ),
                    if (played.isNotEmpty)
                      SliverList.builder(
                        itemCount: played.length,
                        itemBuilder: (context, index) => PlayerTrackRow(
                          song: played[index].song,
                          accent: widget.accent,
                          isPlayed: true,
                          onTap: () => _jumpTo(audioManager, played[index]),
                        ),
                      ),
                    if (current != null)
                      SliverToBoxAdapter(
                        child: StreamBuilder<PlayerState>(
                          stream: audioManager.player.playerStateStream,
                          initialData: audioManager.player.playerState,
                          builder: (context, stateSnapshot) {
                            final playing =
                                stateSnapshot.data?.playing ?? false;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: PlayerTokens.s3,
                                vertical: PlayerTokens.s1,
                              ),
                              child: PlayerTrackRow(
                                song: current.song,
                                accent: widget.accent,
                                isCurrent: true,
                                showAnimatedWave: animatedWave && playing,
                                onIndicatorTap: () {
                                  HapticFeedback.selectionClick();
                                  audioManager.togglePlayPause();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    if (upcoming.isNotEmpty)
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
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: PlayerTokens.s5),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
      ),
      onDismissed: (_) {
        final absolute =
            queue.indexWhere((queued) => queued.queueId == item.queueId);
        if (absolute == -1) return;
        _remove(audioManager, item, absolute);
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
    final label = remaining.isNotEmpty
        ? '${upcoming.length} songs · $remaining'
        : '${upcoming.length} songs remaining';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s5,
        PlayerTokens.s2,
        PlayerTokens.s3,
        0,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: PlayerTokens.meta(context))),
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
              ],
            ),
          );
        }

        return ListView.builder(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: PlayerTokens.s6),
          itemCount: snapshots.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return PlayerSectionHeader(
                label: '${snapshots.length} saved queues',
                trailingLabel: 'Clear all',
                trailingIcon: Icons.delete_sweep_rounded,
                onTrailingTap: _confirmClearAll,
              );
            }

            final snapshot = snapshots[index - 1];
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
}

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s4,
        PlayerTokens.s1,
        PlayerTokens.s4,
        PlayerTokens.s2,
      ),
      // Flat row on the backdrop rather than a card — a list of stacked
      // bordered boxes is exactly the look being avoided here.
      child: Container(
        decoration: BoxDecoration(
          color: expanded ? accent.withValues(alpha: 0.10) : null,
          borderRadius: PlayerTokens.brMd,
        ),
        child: Column(
          children: [
            ListTile(
              onTap: onToggle,
              title: Text(
                snapshot.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PlayerTokens.trackTitle(context).copyWith(fontSize: 15),
              ),
              subtitle: Text(
                '${snapshot.displayDate} · ${snapshot.songFilenames.length} tracks · ${snapshot.source}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PlayerTokens.meta(context),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Restore queue',
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    color: accent,
                    onPressed: onRestore,
                  ),
                  IconButton(
                    tooltip: 'Delete snapshot',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color:
                        Colors.white.withValues(alpha: PlayerTokens.aTertiary),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
            if (expanded) _buildTracks(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildTracks(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(queueSnapshotSongsProvider(snapshot.id));

    return songs.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(PlayerTokens.s4),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(PlayerTokens.s4),
        child: Text('Could not load tracks', style: PlayerTokens.meta(context)),
      ),
      data: (List<Song> tracks) {
        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(PlayerTokens.s4),
            child: Text(
              'None of these tracks are still in your library.',
              style: PlayerTokens.meta(context),
            ),
          );
        }

        return Column(
          children: [
            const Divider(height: 1),
            for (var i = 0; i < tracks.length; i++)
              PlayerTrackRow(
                song: tracks[i],
                accent: accent,
                index: i,
                onTap: onRestore,
              ),
          ],
        );
      },
    );
  }
}

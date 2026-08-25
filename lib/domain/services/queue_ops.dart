import '../../models/queue_item.dart';

/// Pure queue list-planning logic.
///
/// Everything here is a plain function over lists: no player, no database, no
/// I/O. `AudioPlayerManager` decides *when* to call these and performs the
/// resulting player operations; the rules for *what* the queue should look like
/// afterwards live here so they can be unit tested directly.

/// A single planned change to the queue.
///
/// [from] is null for a plain insertion; when it is set the entry already
/// existed at that index and is being moved rather than duplicated.
class QueuePlan {
  /// Index the entry currently sits at, or null when inserting a new entry.
  final int? from;

  /// Index the entry should end up at, once [from] has been removed.
  final int to;

  /// The entry to place at [to]. For a move this is the existing item; for a
  /// copy or an insertion it is a fresh [QueueItem].
  final QueueItem item;

  const QueuePlan({
    required this.to,
    required this.item,
    this.from,
  });

  bool get isMove => from != null;

  @override
  String toString() => 'QueuePlan(from: $from, to: $to, ${item.song.filename})';
}

/// Finds [filename] in [queue], falling back to any of its [mergedSiblings].
///
/// Merged songs map several filenames onto one logical track, so a queue that
/// already holds a sibling counts as already holding the song.
int findInQueue(
  List<QueueItem> queue,
  String filename, {
  List<String> mergedSiblings = const [],
}) {
  final direct = queue.indexWhere((item) => item.song.filename == filename);
  if (direct != -1) return direct;

  for (final sibling in mergedSiblings) {
    final idx = queue.indexWhere((item) => item.song.filename == sibling);
    if (idx != -1) return idx;
  }
  return -1;
}

/// Updates the RAM-based top order queue.
///
/// When [isOverride] is true, [queueId] moves to the front so it plays next.
/// Otherwise, [queueId] is appended to the end of the top order list.
List<String> updateSessionTopOrder(
  List<String> currentOrder,
  String queueId, {
  required bool isOverride,
}) {
  final filtered = currentOrder.where((id) => id != queueId).toList();
  if (isOverride) {
    return [queueId, ...filtered];
  } else {
    return [...filtered, queueId];
  }
}

/// Prunes entries that are no longer upcoming in [queue] (either already played,
/// currently playing, or removed).
List<String> pruneSessionTopOrder(
  List<QueueItem> queue,
  int currentIndex,
  List<String> sessionTopOrder,
) {
  if (sessionTopOrder.isEmpty) return const [];
  return sessionTopOrder.where((id) {
    final idx = queue.indexWhere((item) => item.queueId == id);
    return idx > currentIndex;
  }).toList();
}

/// Plans moving an already-queued upcoming entry to the top section.
///
/// If [queueId] is already present in [sessionTopOrder], this is an override
/// request and it moves immediately after [currentIndex]. Otherwise, it stacks
/// after the last active top entry in [sessionTopOrder] (or right after
/// [currentIndex] if none are present).
QueuePlan? planMoveUpcomingToTop(
  List<QueueItem> queue,
  int currentIndex,
  String queueId, {
  List<String> sessionTopOrder = const [],
}) {
  if (currentIndex < 0 || currentIndex >= queue.length) return null;

  final sourceIndex = queue.indexWhere((item) => item.queueId == queueId);
  if (sourceIndex <= currentIndex) return null;

  final isOverride = sessionTopOrder.contains(queueId);
  final int targetIndex;

  if (isOverride) {
    targetIndex = currentIndex + 1;
  } else {
    var lastTopIndex = currentIndex;
    for (final topId in sessionTopOrder) {
      if (topId == queueId) continue;
      final idx = queue.indexWhere((item) => item.queueId == topId);
      if (idx > currentIndex && idx > lastTopIndex) {
        lastTopIndex = idx;
      }
    }
    targetIndex = lastTopIndex + 1;
  }

  int target = targetIndex.clamp(0, queue.length);
  if (sourceIndex < target) target -= 1;
  if (target < 0 || target >= queue.length) return null;
  if (sourceIndex == target) return null;

  return QueuePlan(
    from: sourceIndex,
    to: target,
    item: queue[sourceIndex],
  );
}

/// Plans "play this next": the entry lands after any previously added top items,
/// or at [currentIndex + 1] if none exist or if overriding an existing top item.
///
/// An entry already in the upcoming queue is *moved* rather than duplicated.
/// Pass [allowDuplicate] to force a second copy anyway.
QueuePlan planPlayNext(
  List<QueueItem> queue,
  int currentIndex,
  QueueItem candidate, {
  List<String> sessionTopOrder = const [],
  List<String> mergedSiblings = const [],
  bool allowDuplicate = false,
}) {
  int existingIdx = -1;
  if (!allowDuplicate) {
    existingIdx = findInQueue(
      queue,
      candidate.song.filename,
      mergedSiblings: mergedSiblings,
    );
  }

  if (existingIdx > currentIndex) {
    final existingItem = queue[existingIdx];
    final isOverride = sessionTopOrder.contains(existingItem.queueId);
    final int targetIndex;

    if (isOverride) {
      targetIndex = (currentIndex + 1).clamp(0, queue.length);
    } else {
      var lastTopIndex = currentIndex;
      for (final topId in sessionTopOrder) {
        if (topId == existingItem.queueId) continue;
        final idx = queue.indexWhere((item) => item.queueId == topId);
        if (idx > currentIndex && idx > lastTopIndex) {
          lastTopIndex = idx;
        }
      }
      targetIndex = (lastTopIndex + 1).clamp(0, queue.length);
    }

    final adjusted = existingIdx >= targetIndex ? targetIndex : targetIndex - 1;
    return QueuePlan(
      from: existingIdx,
      to: adjusted,
      item: existingItem,
    );
  }

  var lastTopIndex = currentIndex;
  for (final topId in sessionTopOrder) {
    final idx = queue.indexWhere((item) => item.queueId == topId);
    if (idx > currentIndex && idx > lastTopIndex) {
      lastTopIndex = idx;
    }
  }
  final targetIndex = (lastTopIndex + 1).clamp(0, queue.length);

  return QueuePlan(to: targetIndex, item: candidate);
}

/// Plans a tap on a queue row: play that entry now.
///
/// An entry that is still upcoming is *moved* to just after the current track,
/// so it exists once. An entry that has already played is *copied* there
/// instead, leaving the played section intact. Either way nothing at or before
/// the current track is disturbed. Returns null when there is nothing to do.
QueuePlan? planJumpTo(List<QueueItem> queue, int currentIndex, String queueId) {
  if (currentIndex < 0 || currentIndex >= queue.length) return null;

  final sourceIndex = queue.indexWhere((item) => item.queueId == queueId);
  if (sourceIndex < 0 || sourceIndex == currentIndex) return null;

  final targetIndex = currentIndex + 1;

  if (sourceIndex > currentIndex) {
    if (sourceIndex == targetIndex) return null;
    return QueuePlan(
      from: sourceIndex,
      to: targetIndex,
      item: queue[sourceIndex],
    );
  }

  // A fresh QueueItem, so the original entry keeps its own identity in the
  // played section rather than being yanked out of history.
  return QueuePlan(
    to: targetIndex,
    item: QueueItem(song: queue[sourceIndex].song),
  );
}

/// Plans a drag-reorder. [newIndex] follows the insertion-slot convention:
/// the slot the entry is dropped into, before its own removal is accounted for.
/// Returns null when the move is a no-op or out of range.
QueuePlan? planReorder(List<QueueItem> queue, int oldIndex, int newIndex) {
  if (queue.isEmpty) return null;
  if (oldIndex < 0 || oldIndex >= queue.length) return null;

  int targetIndex = newIndex.clamp(0, queue.length);
  if (oldIndex < targetIndex) targetIndex -= 1;
  if (targetIndex < 0 || targetIndex >= queue.length) return null;
  if (oldIndex == targetIndex) return null;

  return QueuePlan(from: oldIndex, to: targetIndex, item: queue[oldIndex]);
}

/// Applies a plan to a copy of [queue].
List<QueueItem> applyPlan(List<QueueItem> queue, QueuePlan plan) {
  final next = List<QueueItem>.from(queue);
  final from = plan.from;
  if (from != null) next.removeAt(from);
  next.insert(plan.to.clamp(0, next.length), plan.item);
  return next;
}

/// Sorts [upcoming] back into [originalQueue] order, resuming from where
/// [current] sits in that order and wrapping around to the start — so turning
/// shuffle off continues the album or playlist from the right place rather than
/// jumping back to track one.
List<QueueItem> inOriginalOrder(
  List<QueueItem> upcoming,
  QueueItem current,
  List<QueueItem> originalQueue,
) {
  final byQueueId = <String, int>{};
  final byFilename = <String, int>{};
  for (int i = 0; i < originalQueue.length; i++) {
    byQueueId[originalQueue[i].queueId] = i;
    byFilename.putIfAbsent(originalQueue[i].song.filename, () => i);
  }

  // Duplicated entries carry a fresh queueId, so fall back to the filename.
  int? positionOf(QueueItem item) =>
      byQueueId[item.queueId] ?? byFilename[item.song.filename];

  final anchor = positionOf(current) ?? -1;
  final length = originalQueue.length;

  // Entries the original queue never had — added via Play Next, or generated on
  // the fly — have no natural position, so they keep their relative order at the
  // end rather than being dropped.
  final known = <QueueItem>[];
  final unknown = <QueueItem>[];
  for (final item in upcoming) {
    (positionOf(item) == null ? unknown : known).add(item);
  }

  int rank(QueueItem item) {
    final position = positionOf(item)!;
    return position > anchor ? position : position + length;
  }

  known.sort((a, b) => rank(a).compareTo(rank(b)));
  return [...known, ...unknown];
}

/// One entry of the player's audio source sequence, reduced to what
/// reconciliation needs.
typedef SequenceEntry = ({String filename, String? queueId});

/// Rebuilds the effective queue from the player's own sequence.
///
/// Used to pick up changes made outside the app (notification or headset
/// actions). Entries are matched by queueId first and by filename second, so
/// deliberate duplicates keep their identity instead of collapsing together.
/// [resolveSong] supplies the current library row for a filename; entries it
/// cannot resolve and that are not already queued are dropped.
List<QueueItem> reconcileWithSequence(
  List<QueueItem> effective,
  List<SequenceEntry> sequence,
  QueueItem? Function(String filename) resolveItem,
) {
  final byQueueId = <String, QueueItem>{
    for (final item in effective) item.queueId: item,
  };
  final byFilename = <String, List<QueueItem>>{};
  for (final item in effective) {
    byFilename.putIfAbsent(item.song.filename, () => []).add(item);
  }

  final consumedQueueIds = <String>{};
  final consumedFilenameCounts = <String, int>{};
  final rebuilt = <QueueItem>[];

  for (final entry in sequence) {
    final queueId = entry.queueId;
    QueueItem? resolved;
    if (queueId != null && !consumedQueueIds.contains(queueId)) {
      resolved = byQueueId[queueId];
    }

    if (resolved == null) {
      final candidates = byFilename[entry.filename];
      final usedCount = consumedFilenameCounts[entry.filename] ?? 0;
      if (candidates != null && usedCount < candidates.length) {
        resolved = candidates[usedCount];
        consumedFilenameCounts[entry.filename] = usedCount + 1;
      }
    }

    final fromLibrary = resolveItem(entry.filename);
    if (resolved == null) {
      if (fromLibrary == null) continue;
      resolved = QueueItem(song: fromLibrary.song, queueId: queueId);
    } else {
      resolved = resolved.copyWith(
        song: fromLibrary?.song ?? resolved.song,
        queueId: queueId ?? resolved.queueId,
      );
    }

    consumedQueueIds.add(resolved.queueId);
    rebuilt.add(resolved);
  }

  return rebuilt;
}

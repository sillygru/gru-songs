import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/queue_snapshot.dart';
import '../models/song.dart';
import '../services/database_service.dart';

class QueueHistoryNotifier extends AsyncNotifier<List<QueueSnapshot>> {
  @override
  Future<List<QueueSnapshot>> build() async {
    return _loadSnapshots();
  }

  Future<List<QueueSnapshot>> _loadSnapshots() async {
    final rows = await DatabaseService.instance.getQueueSnapshots();
    return rows.map((row) {
      return QueueSnapshot(
        id: row['id'] as String,
        name: row['name'] as String,
        createdAt: (row['created_at'] as num).toDouble(),
        songFilenames: const [],
        source: row['source'] as String? ?? 'unknown',
      );
    }).toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadSnapshots);
  }

  Future<void> deleteSnapshot(String id) async {
    await DatabaseService.instance.deleteQueueSnapshot(id);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.where((s) => s.id != id).toList());
    }
  }

  Future<void> clearAll() async {
    await DatabaseService.instance.clearQueueHistory();
    state = const AsyncData([]);
  }
}

final queueHistoryProvider =
    AsyncNotifierProvider<QueueHistoryNotifier, List<QueueSnapshot>>(
  QueueHistoryNotifier.new,
);

/// Resolves song filenames for a snapshot to actual Song objects.
final queueSnapshotSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, snapshotId) async {
  final filenames =
      await DatabaseService.instance.getQueueSnapshotSongs(snapshotId);
  final allSongs = await DatabaseService.instance.getAllSongs();
  final songMap = {for (final s in allSongs) s.filename: s};
  return filenames.map((f) => songMap[f]).whereType<Song>().toList();
});

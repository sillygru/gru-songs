import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import '../services/stats_service.dart';
import '../services/user_data_service.dart';
import '../services/audio_player_manager.dart';
import '../services/storage_service.dart';
import '../services/scanner_service.dart';
import '../services/database_service.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../providers/auth_provider.dart';
import 'user_data_provider.dart';

enum SyncStatus { syncing, upToDate, offline, usingCache }

class SyncState {
  final Map<String, SyncStatus> tasks;
  final DateTime? lastSync;
  final bool hasError;

  SyncState({
    this.tasks = const {},
    this.lastSync,
    this.hasError = false,
  });

  SyncStatus get status {
    if (hasError) return SyncStatus.offline;
    if (tasks.values.any((s) => s == SyncStatus.syncing)) {
      return SyncStatus.syncing;
    }
    if (tasks.values.any((s) => s == SyncStatus.usingCache)) {
      return SyncStatus.usingCache;
    }
    return SyncStatus.upToDate;
  }

  SyncState copyWith({
    Map<String, SyncStatus>? tasks,
    DateTime? lastSync,
    bool? hasError,
  }) {
    return SyncState(
      tasks: tasks ?? this.tasks,
      lastSync: lastSync ?? this.lastSync,
      hasError: hasError ?? this.hasError,
    );
  }
}

class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => SyncState();

  void updateTask(String task, SyncStatus status) {
    final newTasks = Map<String, SyncStatus>.from(state.tasks);
    newTasks[task] = status;
    state = state.copyWith(tasks: newTasks, hasError: false);
  }

  void setError() => state = state.copyWith(hasError: true);

  void setUpToDate() {
    final newTasks = Map<String, SyncStatus>.from(state.tasks);
    newTasks.forEach((key, value) => newTasks[key] = SyncStatus.upToDate);
    state = state.copyWith(
        tasks: newTasks, lastSync: DateTime.now(), hasError: false);
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

// Services & Repositories
final apiServiceProvider = Provider<ApiService>((ref) {
  final apiService = ApiService();
  // Update apiService username when auth state changes
  final authState = ref.watch(authProvider);
  apiService.setUsername(authState.username);

  ref.onDispose(() => apiService.dispose());
  return apiService;
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService();
});

final userDataServiceProvider = Provider<UserDataService>((ref) {
  return UserDataService(ref.watch(apiServiceProvider));
});

final scannerServiceProvider = Provider<ScannerService>((ref) {
  return ScannerService();
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(apiServiceProvider));
});

final audioPlayerManagerProvider = Provider<AudioPlayerManager>((ref) {
  final authState = ref.watch(authProvider);
  final manager = AudioPlayerManager(
    ref.watch(apiServiceProvider),
    ref.watch(statsServiceProvider),
    ref.watch(storageServiceProvider),
    authState.username,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

// Data Providers
class SongsNotifier extends AsyncNotifier<List<Song>> {
  @override
  Future<List<Song>> build() async {
    final storage = ref.watch(storageServiceProvider);

    // 1. Load instantly from cache
    final cached = await storage.loadSongs();
    if (cached.isNotEmpty) {
      // Return cached immediately, then update in background
      _backgroundScanUpdate();
      return cached;
    }

    // 2. If no cache, perform initial scan
    return _performFullScan();
  }

  Future<List<Song>> _performFullScan() async {
    final storage = ref.read(storageServiceProvider);
    final scanner = ref.read(scannerServiceProvider);

    final musicPath = await storage.getMusicFolderPath();
    final lyricsPath = await storage.getLyricsFolderPath();

    if (musicPath == null || musicPath.isEmpty) return [];

    final songs =
        await scanner.scanDirectory(musicPath, lyricsPath: lyricsPath);
    await storage.saveSongs(songs);
    return songs;
  }

  Future<void> _backgroundScanUpdate() async {
    try {
      final songs = await _performFullScan();
      state = AsyncValue.data(songs);
    } catch (e) {
      debugPrint('Background scan failed: $e');
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Force a full bidirectional sync of stats, data, and settings
      final auth = ref.read(authProvider);
      if (auth.username != null) {
        await DatabaseService.instance.sync(auth.username!);
        await ref.read(userDataProvider.notifier).refresh();
      }
      return await _performFullScan();
    });
  }

  Future<void> moveSong(Song song, String targetDirectoryPath) async {
    try {
      final oldFile = File(song.url);
      if (!await oldFile.exists()) return;

      final newPath = p.join(targetDirectoryPath, song.filename);
      if (oldFile.path == newPath) return;

      // Ensure target directory exists
      final targetDir = Directory(targetDirectoryPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      await oldFile.rename(newPath);

      // Also try to move lyrics if they exist
      if (song.lyricsUrl != null) {
        final oldLyricsFile = File(song.lyricsUrl!);
        if (await oldLyricsFile.exists()) {
          final lyricsFilename = p.basename(song.lyricsUrl!);
          final newLyricsPath = p.join(targetDirectoryPath, lyricsFilename);
          await oldLyricsFile.rename(newLyricsPath);
        }
      }

      await refresh();
    } catch (e) {
      debugPrint('Error moving song: $e');
      rethrow;
    }
  }
}

final songsProvider =
    AsyncNotifierProvider<SongsNotifier, List<Song>>(SongsNotifier.new);

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});

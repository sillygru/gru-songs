import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/stats_service.dart';
import '../services/user_data_service.dart';
import '../services/audio_player_manager.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../providers/auth_provider.dart';
import 'user_data_provider.dart';

import '../services/storage_service.dart';

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
    if (tasks.values.any((s) => s == SyncStatus.syncing)) return SyncStatus.syncing;
    if (tasks.values.any((s) => s == SyncStatus.usingCache)) return SyncStatus.usingCache;
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
    state = state.copyWith(tasks: newTasks, lastSync: DateTime.now(), hasError: false);
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

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

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(apiServiceProvider));
});

final audioPlayerManagerProvider = Provider<AudioPlayerManager>((ref) {
  final authState = ref.watch(authProvider);
  final manager = AudioPlayerManager(
      ref.watch(apiServiceProvider),
      ref.watch(statsServiceProvider),
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
    
    // Load cache
    final cached = await storage.loadSongs();
    
    if (cached.isNotEmpty) {
      // Set initial status to usingCache if we have cached data
      Future.microtask(() => ref.read(syncProvider.notifier).updateTask('songs', SyncStatus.usingCache));
      _backgroundSync(); // Start background sync
      return cached;
    }
    
    // No cache, must fetch
    return _fetchAndCache();
  }

  Future<void> _backgroundSync() async {
    final api = ref.read(apiServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final syncNotifier = ref.read(syncProvider.notifier);

    try {
      syncNotifier.updateTask('songs', SyncStatus.syncing);
      
      final remoteHashes = await api.fetchSyncHashes();
      final localHashes = await storage.loadSyncHashes();
      
      if (remoteHashes['songs'] == localHashes['songs'] && state.hasValue) {
        // Hashes match, we are up to date!
        syncNotifier.updateTask('songs', SyncStatus.upToDate);
        return;
      }
      
      // Mismatch or no data, fetch fresh
      await _fetchAndCache();
      
      // Update saved hashes
      final newLocalHashes = {...localHashes, 'songs': remoteHashes['songs']!};
      await storage.saveSyncHashes(newLocalHashes);
      
      syncNotifier.updateTask('songs', SyncStatus.upToDate);
    } catch (e) {
      debugPrint('Background sync failed: $e');
      syncNotifier.setError();
    }
  }

  Future<List<Song>> _fetchAndCache() async {
    final repository = ref.read(songRepositoryProvider);
    final storage = ref.read(storageServiceProvider);
    final syncNotifier = ref.read(syncProvider.notifier);

    try {
      if (!state.hasValue || state.isLoading) {
         syncNotifier.updateTask('songs', SyncStatus.syncing);
      }
      
      final songs = await repository.getSongs();
      await storage.saveSongs(songs);
      
      state = AsyncValue.data(songs);
      syncNotifier.updateTask('songs', SyncStatus.upToDate);
      return songs;
    } catch (e) {
      if (state.hasValue) {
        syncNotifier.setError();
        return state.value!;
      }
      syncNotifier.setError();
      rethrow;
    }
  }

  Future<void> refresh() async {
    await _backgroundSync();
  }
}

final songsProvider = AsyncNotifierProvider<SongsNotifier, List<Song>>(SongsNotifier.new);

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});

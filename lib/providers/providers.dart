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
    
    // If we have cache, return it immediately and fetch fresh data in background
    if (cached.isNotEmpty) {
      _fetchAndCache(); // Fire and forget background update
      return cached;
    }
    
    // No cache, fetch and wait
    return _fetchAndCache();
  }

  Future<List<Song>> _fetchAndCache() async {
    final repository = ref.read(songRepositoryProvider);
    final storage = ref.read(storageServiceProvider);
    try {
      final songs = await repository.getSongs();
      await storage.saveSongs(songs);
      
      // If we weren't already waiting on this future (i.e. we returned cache in build),
      // we need to manually update state.
      if (state.hasValue && !state.isLoading) {
         state = AsyncValue.data(songs);
      }
      return songs;
    } catch (e) {
      // If we have data (cache), preserve it.
      if (state.hasValue) {
        // Maybe log error or show transient error?
        // For now, we just swallow the error to keep showing cache
        // but we could rethrow if we want the UI to know (but that might replace data with error)
        return state.value!;
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    // Force a refresh.
    // We set state to loading (optional, but good for pull-to-refresh feedback if desired,
    // though usually pull-to-refresh handles its own spinner)
    // Actually standard RefresIndicator expects the Future to complete.
    
    // If we want to keep showing data while refreshing:
    // state = AsyncValue.loading(); // This clears data? No, usually .loading() is a state.
    // AsyncValue.data(previous).copyWithPrevious(...)
    
    // Simplest: just await _fetchAndCache. 
    // The state update in _fetchAndCache will notify listeners.
    await _fetchAndCache();
  }
}

final songsProvider = AsyncNotifierProvider<SongsNotifier, List<Song>>(SongsNotifier.new);

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});

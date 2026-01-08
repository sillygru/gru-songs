import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/stats_service.dart';
import '../services/user_data_service.dart';
import '../services/audio_player_manager.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../providers/auth_provider.dart';
import 'user_data_provider.dart';

// Services & Repositories
final apiServiceProvider = Provider<ApiService>((ref) {
  final apiService = ApiService();
  // Update apiService username when auth state changes
  final authState = ref.watch(authProvider);
  apiService.setUsername(authState.username);
  
  ref.onDispose(() => apiService.dispose());
  return apiService;
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
final songsProvider = FutureProvider<List<Song>>((ref) async {
  final repository = ref.watch(songRepositoryProvider);
  return repository.getSongs();
});

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});

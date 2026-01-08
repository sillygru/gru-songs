import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_player_manager.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';

// Services & Repositories
final apiServiceProvider = Provider<ApiService>((ref) {
  final apiService = ApiService();
  ref.onDispose(() => apiService.dispose());
  return apiService;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(apiServiceProvider));
});

final audioPlayerManagerProvider = Provider<AudioPlayerManager>((ref) {
  final manager = AudioPlayerManager(ref.watch(apiServiceProvider));
  ref.onDispose(() => manager.dispose());
  return manager;
});

// Data Providers
final songsProvider = FutureProvider<List<Song>>((ref) async {
  final repository = ref.watch(songRepositoryProvider);
  return repository.getSongs();
});

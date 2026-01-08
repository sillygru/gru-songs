import '../../models/song.dart';
import '../../services/api_service.dart';

class SongRepository {
  final ApiService _apiService;

  SongRepository(this._apiService);

  Future<List<Song>> getSongs() async {
    return _apiService.fetchSongs();
  }

  Future<String?> getLyrics(String url) async {
    return _apiService.fetchLyrics(url);
  }
}

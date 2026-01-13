import '../../models/song.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';

class SongRepository {
  final ApiService _apiService;

  SongRepository(this._apiService);

  Future<List<Song>> getSongs() async {
    return _apiService.fetchSongs();
  }

  Future<String?> getLyrics(String url) async {
    final filename = url.split('/').last;
    return CacheService.instance.readString('lyrics', filename, _apiService.getFullUrl(url));
  }
}

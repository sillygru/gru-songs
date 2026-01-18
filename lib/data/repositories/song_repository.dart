import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../models/song.dart';
import '../../services/api_service.dart';

class SongRepository {
  final ApiService _apiService;

  SongRepository(this._apiService);

  Future<List<Song>> getSongs() async {
    return _apiService.fetchSongs();
  }

  Future<String?> getLyrics(String url) async {
    if (url.startsWith('/') || url.startsWith('C:\\')) {
      try {
        final file = File(url);
        if (await file.exists()) {
          return await file.readAsString();
        }
      } catch (e) {
        debugPrint('Error reading local lyrics: $e');
      }
      return null;
    }
    return _apiService.fetchLyrics(url);
  }
}

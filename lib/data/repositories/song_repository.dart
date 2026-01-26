import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../models/song.dart';

class SongRepository {
  SongRepository();

  Future<List<Song>> getSongs() async {
    // Local-only - songs are managed by the scanner service
    return [];
  }

  Future<String?> getLyrics(String url) async {
    if (url.startsWith('/') || url.startsWith('C:\\')) {
      try {
        final file = File(url);
        if (await file.exists()) {
          return await file.readAsString();
        }
      } catch (e) {
        debugPrint('Error reading lyrics file: $e');
      }
    }
    return null;
  }
}

import 'package:flutter/foundation.dart';
import '../../models/song.dart';
import '../../services/ffmpeg_service.dart';

class SongRepository {
  final FFmpegService _ffmpegService = FFmpegService();

  SongRepository();

  Future<List<Song>> getSongs() async {
    // Local-only - songs are managed by the scanner service
    return [];
  }

  /// Gets lyrics from embedded metadata in the audio file using FFmpeg.
  /// Always tries to read lyrics regardless of hasLyrics flag.
  Future<String?> getLyrics(Song song) async {
    if (kDebugMode) {
      debugPrint('SongRepository: Getting lyrics for ${song.filename}');
      debugPrint('SongRepository: File path: ${song.url}');
      debugPrint('SongRepository: hasLyrics flag: ${song.hasLyrics}');
    }

    final lyrics = await _ffmpegService.getLyrics(song.url);

    if (kDebugMode) {
      if (lyrics != null) {
        debugPrint('SongRepository: Found lyrics (${lyrics.length} chars)');
      } else {
        debugPrint('SongRepository: No lyrics found');
      }
    }

    return lyrics;
  }
}

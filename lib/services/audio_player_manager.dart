import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'api_service.dart';

class AudioPlayerManager {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;

  AudioPlayerManager(this._apiService);
  
  AudioPlayer get player => _player;

  Future<void> init(List<Song> songs) async {
    try {
      // ignore: deprecated_member_use
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.uri(
            Uri.parse(_apiService.getFullUrl(song.url)),
            tag: MediaItem(
              id: song.filename,
              album: song.album,
              title: song.title,
              artist: song.artist,
              artUri: song.coverUrl != null 
                  ? Uri.parse(_apiService.getFullUrl(song.coverUrl!)) 
                  : null,
              extras: {
                'lyricsUrl': song.lyricsUrl,
              },
            ),
          );
        }).toList(),
      );

      await _player.setVolume(1.0);
      await _player.setAudioSource(playlist);
    } catch (e) {
      if (e.toString().contains('Loading interrupted')) {
        debugPrint("Audio loading interrupted (safe to ignore): $e");
      } else {
        debugPrint("Error loading audio source: $e");
      }
    }
  }

  void dispose() {
    _player.dispose();
  }
}

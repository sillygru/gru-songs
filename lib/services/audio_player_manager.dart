import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'api_service.dart';

class AudioPlayerManager {
  final AudioPlayer _player = AudioPlayer();
  
  AudioPlayer get player => _player;

  Future<void> init(List<Song> songs) async {
    try {
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.uri(
            Uri.parse(ApiService.getFullUrl(song.url)),
                      tag: MediaItem(
                        id: song.filename,
                        album: song.album,
                        title: song.title,
                        artist: song.artist,
                        artUri: song.coverUrl != null 
                            ? Uri.parse(ApiService.getFullUrl(song.coverUrl!)) 
                            : Uri.parse(ApiService.getFullUrl('/stream/cover.jpg')),
                        extras: {
                          'lyricsUrl': song.lyricsUrl,
                        },
                      ),
            
          );
        }).toList(),
      );

      // Set volume to max and remove preload: false to let it buffer naturally
      await _player.setVolume(1.0);
      await _player.setAudioSource(playlist);
    } catch (e) {
      if (e.toString().contains('Loading interrupted')) {
        // This can happen if the user navigates away or retries quickly
        print("Audio loading interrupted (safe to ignore): $e");
      } else {
        print("Error loading audio source: $e");
      }
    }
  }

  void dispose() {
    _player.dispose();
  }
}

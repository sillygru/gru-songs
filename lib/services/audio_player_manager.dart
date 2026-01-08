import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'api_service.dart';
import 'stats_service.dart';

class AudioPlayerManager {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  final StatsService _statsService;
  final String? _username;
  
  DateTime? _lastPlayStartTime;
  String? _currentSongFilename;

  AudioPlayerManager(this._apiService, this._statsService, this._username) {
    _initStatsListeners();
  }
  
  AudioPlayer get player => _player;
  
  void _initStatsListeners() {
    _player.playerStateStream.listen((state) {
      if (_username == null) return;
      
      if (state.playing) {
        if (_lastPlayStartTime == null) {
            _lastPlayStartTime = DateTime.now();
            _trackEvent('play');
        }
      } else {
        if (_lastPlayStartTime != null) {
          final duration = DateTime.now().difference(_lastPlayStartTime!).inSeconds.toDouble();
          if (duration > 0) {
             _trackEvent('pause', duration: duration);
          }
          _lastPlayStartTime = null;
        }
      }
      
      if (state.processingState == ProcessingState.completed) {
         _trackEvent('complete');
      }
    });
    
    _player.currentIndexStream.listen((index) {
       // Identify current song
       if (index != null && _player.sequence != null && index < _player.sequence!.length) {
         final source = _player.sequence![index] as UriAudioSource;
         // Extract filename from ID or Tag
         // We set ID as filename in MediaItem
         if (source.tag is MediaItem) {
           _currentSongFilename = (source.tag as MediaItem).id;
         }
       }
    });
  }
  
  void _trackEvent(String eventType, {double duration = 0}) {
    if (_username != null && _currentSongFilename != null) {
      _statsService.track(_username!, _currentSongFilename!, duration, eventType);
    }
  }

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

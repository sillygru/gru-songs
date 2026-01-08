import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'api_service.dart';
import 'stats_service.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  final StatsService _statsService;
  final String? _username;
  
  // Stats tracking state
  String? _currentSongFilename;
  DateTime? _playStartTime;
  double _accumulatedDuration = 0.0;

  AudioPlayerManager(this._apiService, this._statsService, this._username) {
    WidgetsBinding.instance.addObserver(this);
    _initStatsListeners();
  }
  
  AudioPlayer get player => _player;
  
  void _initStatsListeners() {
    // 1. Listen for playback state changes (Play/Pause)
    _player.playerStateStream.listen((state) {
      if (_username == null) return;
      
      if (state.playing) {
        // Started playing
        _playStartTime ??= DateTime.now();
      } else {
        // Paused or stopped
        if (_playStartTime != null) {
          _accumulatedDuration += DateTime.now().difference(_playStartTime!).inMilliseconds / 1000.0;
          _playStartTime = null;
        }
      }
      
      // Handle natural completion
      if (state.processingState == ProcessingState.completed) {
         _flushStats(eventType: 'complete');
      }
    });
    
    // 2. Listen for song changes (Sequence State)
    // This detects skips/next/prev
    _player.sequenceStateStream.listen((state) {
        final currentItem = state.currentSource?.tag;
        
        if (currentItem is MediaItem) {
            final newFilename = currentItem.id;
            
            // If the song changed, flush stats for the OLD song
            if (_currentSongFilename != null && _currentSongFilename != newFilename) {
                _flushStats(eventType: 'skip');
            }
            
            // Set new song
            if (_currentSongFilename != newFilename) {
                _currentSongFilename = newFilename;
                _accumulatedDuration = 0.0;
                _playStartTime = _player.playing ? DateTime.now() : null;
            }
        }
    });
  }
  
  void _flushStats({required String eventType}) {
    if (_username == null || _currentSongFilename == null) return;
    
    // Calculate final duration
    double finalDuration = _accumulatedDuration;
    if (_playStartTime != null) {
       finalDuration += DateTime.now().difference(_playStartTime!).inMilliseconds / 1000.0;
       // We don't reset _playStartTime here because we might continue playing the same song 
       // (e.g. if this flush was triggered by app backgrounding but audio continues)
       // BUT if this is a 'skip' or 'complete', we reset.
    }
    
    if (finalDuration > 0.5) { // Ignore tiny blips
        _statsService.track(_username!, _currentSongFilename!, finalDuration, eventType);
    }
    
    // Reset counters
    _accumulatedDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
        _playStartTime = null; // Prepare for next song
    } else {
        // If we just flushed due to backgrounding but are still playing, 
        // we effectively "reset" the start time to NOW so we don't double count.
        if (_playStartTime != null) {
            _playStartTime = DateTime.now();
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
       // App going to background/closed.
       // Note: JustAudioBackground might keep it playing.
       // If we want to track "Active App Usage Listening" vs "Background Listening", this is where we split.
       // However, to be safe against kills, maybe we flush 'intermediate' stats?
       // Let's flush 'listen' event (generic) and reset accumulator.
       // _flushStats(eventType: 'listen_segment');
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

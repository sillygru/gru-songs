import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
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
  
  // Queue management
  List<Song> _originalSongs = [];
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);

  AudioPlayerManager(this._apiService, this._statsService, this._username) {
    WidgetsBinding.instance.addObserver(this);
    _initStatsListeners();
    _initPersistence();
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
                _saveLastSong(newFilename);
            }
        }
    });
  }

  void _initPersistence() {
    // Already handled in listeners
  }

  Future<void> _saveLastSong(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_song_filename', filename);
  }

  Future<String?> _getLastSong() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_song_filename');
  }
  
  void _flushStats({required String eventType}) {
    if (_username == null || _currentSongFilename == null) return;
    
    // Calculate final duration
    double finalDuration = _accumulatedDuration;
    if (_playStartTime != null) {
       finalDuration += DateTime.now().difference(_playStartTime!).inMilliseconds / 1000.0;
    }
    
    if (finalDuration > 0.5) { // Ignore tiny blips
        _statsService.track(_username!, _currentSongFilename!, finalDuration, eventType);
    }
    
    // Reset counters
    _accumulatedDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
        _playStartTime = null; // Prepare for next song
    } else {
        if (_playStartTime != null) {
            _playStartTime = DateTime.now();
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    _originalSongs = List.from(songs);
    shuffleNotifier.value = false; // Reset shuffle state on new init
    
    try {
      final audioSources = songs.map((song) {
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
              'origin': 'context', // Mark as part of the original context
            },
          ),
        );
      }).toList();

      int initialIndex = 0;
      if (autoSelect && songs.isNotEmpty) {
        final lastSongFilename = await _getLastSong();
        int foundIndex = -1;
        
        if (lastSongFilename != null) {
          foundIndex = songs.indexWhere((s) => s.filename == lastSongFilename);
        }
        
        if (foundIndex != -1) {
          initialIndex = foundIndex;
        } else {
          initialIndex = Random().nextInt(songs.length);
        }
      }

      await _player.setVolume(1.0);
      await _player.setAudioSources(audioSources, initialIndex: initialIndex);
    } catch (e) {
      if (e.toString().contains('Loading interrupted')) {
        debugPrint("Audio loading interrupted (safe to ignore): $e");
      } else {
        debugPrint("Error loading audio source: $e");
      }
    }
  }

  Future<void> toggleShuffle() async {
    if (shuffleNotifier.value) {
      await _unshuffleQueue();
    } else {
      await _shuffleQueue();
    }
  }
  
  Future<void> _shuffleQueue() async {
    try {
        final currentAudioSource = _player.audioSource;
        if (currentAudioSource is! ConcatenatingAudioSource) return;

        final source = currentAudioSource;
        final currentIndex = _player.currentIndex ?? 0;
        final children = source.children;
        
        final upcomingContext = <AudioSource>[]; // These we will shuffle
        
        // Scan upcoming
        for (int i = currentIndex + 1; i < children.length; i++) {
            upcomingContext.add(children[i]);
        }
        
        // Shuffle the context songs
        upcomingContext.shuffle();
        
        // Remove everything after current
        if (currentIndex + 1 < children.length) {
            await source.removeRange(currentIndex + 1, children.length);
        }
        
        // Add back shuffled context
        await source.addAll(upcomingContext);
        
        shuffleNotifier.value = true;
        
    } catch (e) {
        debugPrint("Error shuffling queue: $e");
    }
  }
  
  Future<void> _unshuffleQueue() async {
      try {
        final currentAudioSource = _player.audioSource;
        if (currentAudioSource is! ConcatenatingAudioSource) return;

        final source = currentAudioSource;
        final currentIndex = _player.currentIndex ?? 0;
        final children = source.children;
        
        // 2. Determine where to resume in _originalSongs
        int resumeIndex = -1;
        
        // Check current song
        final currentSource = children[currentIndex];
        String? currentId;
        if (currentSource is UriAudioSource) {
            currentId = (currentSource.tag as MediaItem).id;
        }
        
        if (currentId != null) {
             resumeIndex = _originalSongs.indexWhere((s) => s.filename == currentId);
        }
        
        final restoredContext = <AudioSource>[];
        final startPixel = resumeIndex + 1;
        
        if (startPixel < _originalSongs.length) {
            for (int i = startPixel; i < _originalSongs.length; i++) {
                final song = _originalSongs[i];
                restoredContext.add(AudioSource.uri(
                     Uri.parse(_apiService.getFullUrl(song.url)),
                     tag: MediaItem(
                        id: song.filename,
                        album: song.album,
                        title: song.title,
                        artist: song.artist,
                        artUri: song.coverUrl != null ? Uri.parse(_apiService.getFullUrl(song.coverUrl!)) : null,
                        extras: {'lyricsUrl': song.lyricsUrl, 'origin': 'context'},
                     )
                 ));
            }
        }
        
        // 3. Rebuild Queue
        // Remove everything after current
        if (currentIndex + 1 < children.length) {
            await source.removeRange(currentIndex + 1, children.length);
        }
        
        // Add restored context
        await source.addAll(restoredContext);
        
        shuffleNotifier.value = false;
        
      } catch (e) {
          debugPrint("Error unshuffling queue: $e");
      }
  }

  void dispose() {
    _player.dispose();
    shuffleNotifier.dispose();
  }
}


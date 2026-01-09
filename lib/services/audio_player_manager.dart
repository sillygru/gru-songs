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

  Future<void> playNext(Song song) async {
    try {
      final newSource = AudioSource.uri(
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
            'origin': 'manual', // Mark as manually added
          },
        ),
      );

      if (_player.audioSource is ConcatenatingAudioSource) {
          final source = _player.audioSource as ConcatenatingAudioSource;
          final currentIndex = _player.currentIndex ?? 0;
          final children = source.children;
          
          // Find where to insert: After current + after any consecutive 'manual' songs
          int insertIndex = currentIndex + 1;
          for (int i = currentIndex + 1; i < children.length; i++) {
             final child = children[i];
             if (child is UriAudioSource) {
                 final tag = child.tag as MediaItem;
                 if (tag.extras?['origin'] == 'manual') {
                     insertIndex++;
                 } else {
                     break; // Stop at first non-manual song
                 }
             }
          }
          
          // Bounds check
          if (insertIndex > children.length) {
              insertIndex = children.length;
          }
          
          await source.insert(insertIndex, newSource);
      } else {
          // Single source fallback
          final currentSource = _player.audioSource;
          if (currentSource != null) {
              final newPlaylist = ConcatenatingAudioSource(
                  children: [
                      currentSource,
                      newSource,
                  ],
              );
              final position = _player.position;
              await _player.setAudioSource(newPlaylist, initialIndex: 0, initialPosition: position);
          }
      }
      
    } catch (e) {
      debugPrint("Error adding song to play next: $e");
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
        
        // 1. Identify "Priority" items (Current + Upcoming Manuals)
        final priorityItems = <AudioSource>[];
        
        // Add current song (if not null, though currentIndex implies it exists)
        // Wait, we don't move the current song. We only shuffle UPCOMING.
        // So we leave 0...currentIndex as is? 
        // No, standard behavior: Previous songs are history. We can leave them.
        // We only shuffle from currentIndex + 1 onwards.
        
        final upcomingManuals = <AudioSource>[];
        final upcomingContext = <AudioSource>[]; // These we will shuffle
        
        // Scan upcoming
        for (int i = currentIndex + 1; i < children.length; i++) {
            final child = children[i];
            if (child is UriAudioSource) {
               final tag = child.tag as MediaItem;
               if (tag.extras?['origin'] == 'manual') {
                   upcomingManuals.add(child);
               } else {
                   // It's a context song (or unknown), add to shuffle pool
                   upcomingContext.add(child);
               }
            }
        }
        
        // Also need to pull in any "Context" songs that are NOT in the current queue
        // (e.g. if we are already shuffled, and re-shuffling? Or if we playNext'd and pushed things down?)
        // Actually, if we are turning Shuffle ON, we assume the current queue reflects the "Unshuffled" state (mostly).
        // But if we are in "Unshuffled" mode, the queue matches _originalSongs order (with manuals interspersed).
        // So 'upcomingContext' currently contains the rest of the album in order.
        
        // Shuffle the context songs
        upcomingContext.shuffle();
        
        // Remove everything after current
        if (currentIndex + 1 < children.length) {
            await source.removeRange(currentIndex + 1, children.length);
        }
        
        // Add back manuals (ordered)
        await source.addAll(upcomingManuals);
        
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
        
        // 1. Identify upcoming manuals to preserve
        final upcomingManuals = <AudioSource>[];
        
        // Scan upcoming for manuals
        for (int i = currentIndex + 1; i < children.length; i++) {
            final child = children[i];
            if (child is UriAudioSource) {
               final tag = child.tag as MediaItem;
               if (tag.extras?['origin'] == 'manual') {
                   upcomingManuals.add(child);
               }
            }
        }

        // 2. Determine where to resume in _originalSongs
        // Find the "Anchor" song to decide what comes next.
        // If current song is Context, it's the anchor.
        // If current song is Manual, look for the first upcoming Context song in the current queue? 
        // Or just resume from the beginning if we are lost?
        
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
        
        // If current is not in original (e.g. manual), try to find a hint from upcoming context songs
        if (resumeIndex == -1) {
             for (int i = currentIndex + 1; i < children.length; i++) {
                final child = children[i];
                if (child is UriAudioSource) {
                    final tag = child.tag as MediaItem;
                    if (tag.extras?['origin'] == 'context') {
                         final id = tag.id;
                         final found = _originalSongs.indexWhere((s) => s.filename == id);
                         if (found != -1) {
                             // We found a context song coming up. 
                             // We should resume from BEFORE this one? 
                             // No, if we unshuffle, we want to restore the NATURAL order.
                             // If we are currently playing a manual song, and the next context song was #5.
                             // Natural order says #5 comes after #4. 
                             // So maybe we resume from #5?
                             resumeIndex = found - 1; // So that #5 is next? 
                             // Wait, we append starting from resumeIndex + 1.
                             // So if found is #5, we want #5 to be the first added.
                             // So resumeIndex should be #4 (found - 1).
                             break;
                         }
                    }
                }
             }
        }
        
        // If still -1, fallback to 0 (restart context from beginning)
        // Or if the current manual song was added at the very end, maybe we just append nothing?
        // Let's default to -1 implies "start from beginning" if we can't find place.
        
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
        
        // Add manuals back
        await source.addAll(upcomingManuals);
        
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


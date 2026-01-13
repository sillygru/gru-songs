import 'dart:async';
import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/shuffle_config.dart';
import 'cache_service.dart';
import 'api_service.dart';
import 'stats_service.dart';
import 'storage_service.dart';
import 'shuffle_manager.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  final StatsService _statsService;
  final StorageService _storageService = StorageService();
  final String? _username;
  
  late ConcatenatingAudioSource _playlist;
  List<QueueItem> _originalQueue = [];
  List<QueueItem> _effectiveQueue = [];
  
  // Stats tracking state
  String? _currentSongFilename;
  DateTime? _playStartTime;
  
  // New stats counters
  double _foregroundDuration = 0.0;
  double _backgroundDuration = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);

  ShuffleConfig _shuffleConfig = const ShuffleConfig();
  List<String> _shuffleHistory = [];
  Set<String> _favorites = {};
  Set<String> _suggestLess = {};
  final Completer<void> _initCompleter = Completer<void>();

  AudioPlayerManager(
    this._apiService, 
    this._statsService, 
    this._username, {
    Set<String> initialFavorites = const {},
    Set<String> initialSuggestLess = const {},
  }) : _favorites = initialFavorites,
       _suggestLess = initialSuggestLess {
    WidgetsBinding.instance.addObserver(this);
    _initStatsListeners();
    _loadShuffleState().then((_) => _initCompleter.complete());
  }
  
  void updateUserPreferences({required Set<String> favorites, required Set<String> suggestLess}) {
    _favorites = favorites;
    _suggestLess = suggestLess;
  }
  
  AudioPlayer get player => _player;

  Future<void> _loadShuffleState() async {
    if (_username == null) return;

    // 1. Load from local cache for speed
    final localState = await _storageService.loadShuffleState(_username!);
    if (localState != null) {
      _applyLoadedShuffleState(localState);
    }

    // 2. Load from backend if online
    try {
      final remoteState = await _apiService.fetchShuffleState();
      _applyLoadedShuffleState(remoteState);
      // Update local cache
      await _storageService.saveShuffleState(_username!, remoteState);
    } catch (e) {
      debugPrint("Failed to fetch remote shuffle state: $e");
    }
  }

  void _applyLoadedShuffleState(Map<String, dynamic> state) {
    shuffleNotifier.value = state['shuffle_enabled'] ?? false;
    if (state['shuffle_config'] != null) {
      _shuffleConfig = ShuffleConfig.fromJson(state['shuffle_config']);
    }
    if (state['shuffle_history'] != null) {
      _shuffleHistory = List<String>.from(state['shuffle_history']);
    }
  }

  Future<void> _saveShuffleState() async {
    if (_username == null) return;
    
    final state = {
      'shuffle_enabled': shuffleNotifier.value,
      'shuffle_config': _shuffleConfig.toJson(),
      'shuffle_history': _shuffleHistory,
    };

    // Save locally
    await _storageService.saveShuffleState(_username!, state);

    // Save to backend (fire and forget or background)
    _apiService.updateShuffleState(state).catchError((e) {
      debugPrint("Failed to update remote shuffle state: $e");
    });
  }
  
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
          _updateDurations();
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
        final currentSource = state.currentSource;
        if (currentSource == null) return;
        final currentItem = currentSource.tag;
        
        if (currentItem is MediaItem) {
            final newFilename = currentItem.id;
            
            // If the song changed, flush stats for the OLD song
            if (_currentSongFilename != null && _currentSongFilename != newFilename) {
                _flushStats(eventType: 'skip');
            }
            
            // Set new song
            if (_currentSongFilename != newFilename) {
                _currentSongFilename = newFilename;
                _foregroundDuration = 0.0;
                _backgroundDuration = 0.0;
                _playStartTime = _player.playing ? DateTime.now() : null;
                _saveLastSong(newFilename);
                
                // Add to shuffle history
                if (!_shuffleHistory.contains(newFilename)) {
                  _shuffleHistory.add(newFilename);
                  if (_shuffleHistory.length > 50) _shuffleHistory.removeAt(0);
                  _saveShuffleState();
                }

                // Background cache verification for the NEW song
                _verifyCurrentSongCache(currentItem);
            }
        }
    });
  }

  Future<void> _verifyCurrentSongCache(MediaItem item) async {
    final url = item.extras?['remoteUrl'] as String?;
    if (url == null) return;

    try {
      // New CacheService handles background validation and replacement
      await CacheService.instance.getFile('songs', item.id, url);
      debugPrint("Background cache check completed for: ${item.title}");
    } catch (e) {
      debugPrint("Background cache check failed for ${item.title}: $e");
    }
  }

  Future<void> _saveLastSong(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_song_filename', filename);
  }

  Future<String?> _getLastSong() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_song_filename');
  }
  
  void _updateDurations() {
    if (_playStartTime != null) {
      final now = DateTime.now();
      final diff = now.difference(_playStartTime!).inMilliseconds / 1000.0;
      
      if (_appLifecycleState == AppLifecycleState.resumed) {
        _foregroundDuration += diff;
      } else {
        _backgroundDuration += diff;
      }
      // Note: We don't nullify _playStartTime here unless pausing
    }
  }
  
  void _flushStats({required String eventType}) {
    if (_username == null || _currentSongFilename == null) return;
    
    // Capture final chunk of time if playing
    if (_playStartTime != null) {
       _updateDurations();
    }
    
    double finalDuration = _foregroundDuration + _backgroundDuration;
    
    if (finalDuration > 0.5) { // Ignore tiny blips
        _statsService.track(
          _username!, 
          _currentSongFilename!, 
          finalDuration, 
          eventType,
          foregroundDuration: _foregroundDuration,
          backgroundDuration: _backgroundDuration
        );
    }
    
    // Reset counters
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    
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
    // If playing, attribute time spent in previous state
    if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = DateTime.now(); // Reset start time for the new state
    }
    _appLifecycleState = state;
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    await _initCompleter.future;
    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _effectiveQueue = List.from(_originalQueue);
    
    try {
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

      if (shuffleNotifier.value) {
        // Apply shuffle to the initial queue if enabled
        _applyShuffle(initialIndex);
        initialIndex = 0; // After _applyShuffle, currentItem is at 0
      }

      // Prepare playlist
      _playlist = ConcatenatingAudioSource(children: []);
      final sources = await Future.wait(_effectiveQueue.map((item) => _createAudioSource(item)));
      await _playlist.addAll(sources);

      await _player.setVolume(1.0);
      await _player.setAudioSource(_playlist, initialIndex: initialIndex);
      
      _updateQueueNotifier();

      // Listen for current index changes to cache upcoming songs
      _player.currentIndexStream.listen((index) {
        if (index != null) {
          _cacheSurroundingSongs(index, _effectiveQueue);
        }
      });
      
    } catch (e) {
      if (e.toString().contains('Loading interrupted')) {
        debugPrint("Audio loading interrupted (safe to ignore): $e");
      } else {
        debugPrint("Error loading audio source: $e");
      }
    }
  }

  Future<AudioSource> _createAudioSource(QueueItem item) async {
    final song = item.song;
    final url = _apiService.getFullUrl(song.url);
    final uri = await CacheService.instance.getAudioUri(
      song.filename, 
      url, 
      version: song.mtime?.toString(),
      triggerDownload: false
    );

    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: song.filename,
        album: song.album,
        title: song.title ?? 'No Title',
        artist: song.artist,
        duration: song.duration,
        artUri: song.coverUrl != null 
            ? Uri.parse(_apiService.getFullUrl(song.coverUrl!)) 
            : null,
        extras: {
          'lyricsUrl': song.lyricsUrl,
          'remoteUrl': url,
          'queueId': item.queueId,
          'isPriority': item.isPriority,
        },
      ),
    );
  }
  
  void _updateQueueNotifier() {
    queueNotifier.value = List.from(_effectiveQueue);
  }

  void _cacheSurroundingSongs(int currentIndex, List<QueueItem> queue) {
     for (int i = currentIndex; i < min(currentIndex + 3, queue.length); i++) {
        final song = queue[i].song;
        final url = _apiService.getFullUrl(song.url);
        CacheService.instance.getFile('songs', song.filename, url, version: song.mtime?.toString(), triggerDownload: true).then((_) {
        }).catchError((e) {
           debugPrint("Failed to background cache ${song.title}: $e");
        });
     }
  }

  Future<void> shuffleAndPlay(List<Song> songs) async {
    if (songs.isEmpty) return;
    await init(songs);
    
    final randomIndex = Random().nextInt(songs.length);
    // Move random song to start if we want to play immediately
    // but better to just seek.
    await _player.seek(Duration.zero, index: randomIndex);
    
    // Enable shuffle
    shuffleNotifier.value = true;
    _applyShuffle(randomIndex);
    await _saveShuffleState();
    
    await _player.play();
  }

  Future<void> toggleShuffle() async {
    final isShuffle = !shuffleNotifier.value;
    shuffleNotifier.value = isShuffle;
    
    final currentIndex = _player.currentIndex ?? 0;
    if (isShuffle) {
      _applyShuffle(currentIndex);
    } else {
      _applyLinear(currentIndex);
    }
    await _saveShuffleState();
  }

  void _applyShuffle(int currentIndex) {
    _effectiveQueue = ShuffleManager.applyShuffle(
      effectiveQueue: _effectiveQueue,
      currentIndex: currentIndex,
      config: _shuffleConfig,
      history: _shuffleHistory,
      favorites: _favorites,
      suggestLess: _suggestLess,
    );
    
    _rebuildPlaylist(initialIndex: 0);
  }

  void _applyLinear(int currentIndex) {
    if (_effectiveQueue.isEmpty) return;
    
    final currentItem = _effectiveQueue[currentIndex];
    
    final priorityItems = _effectiveQueue.where((item) => item.isPriority && item != currentItem).toList();
    final originalItems = _originalQueue.where((item) => !priorityItems.any((p) => p.queueId == item.queueId)).toList();
    
    int originalIdx = originalItems.indexWhere((item) => item.song.filename == currentItem.song.filename);

    if (originalIdx != -1) {
      _effectiveQueue = [
        ...originalItems.sublist(0, originalIdx),
        currentItem,
        ...priorityItems,
        ...originalItems.sublist(originalIdx + 1),
      ];
    } else {
      _effectiveQueue = [
        currentItem,
        ...priorityItems,
        ...originalItems,
      ];
    }
    
    int newIndex = _effectiveQueue.indexOf(currentItem);
    _rebuildPlaylist(initialIndex: newIndex);
  }

  Future<void> _rebuildPlaylist({int? initialIndex}) async {
    if (_effectiveQueue.isEmpty) return;
    
    final playing = _player.playing;
    final position = _player.position;
    final targetIndex = initialIndex ?? _player.currentIndex ?? 0;
    
    final sources = await Future.wait(_effectiveQueue.map((item) => _createAudioSource(item)));
    
    final newPlaylist = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(
      newPlaylist,
      initialIndex: targetIndex,
      initialPosition: position,
    );
    
    _playlist = newPlaylist;
    
    if (playing) await _player.play();
    _updateQueueNotifier();
  }

  Future<void> playNext(Song song) async {
    final currentIndex = _player.currentIndex ?? -1;
    final item = QueueItem(song: song, isPriority: true);
    
    _effectiveQueue.insert(currentIndex + 1, item);
    final source = await _createAudioSource(item);
    await _playlist.insert(currentIndex + 1, source);
    
    _updateQueueNotifier();
    _cacheSurroundingSongs(currentIndex, _effectiveQueue);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    final item = _effectiveQueue.removeAt(oldIndex);
    _effectiveQueue.insert(newIndex, item);
    
    // Note: just_audio's move is very efficient
    await _playlist.move(oldIndex, newIndex);
    
    _updateQueueNotifier();
    
    final currentIndex = _player.currentIndex ?? 0;
    _cacheSurroundingSongs(currentIndex, _effectiveQueue);
  }

  Future<void> removeFromQueue(int index) async {
    final currentIndex = _player.currentIndex ?? -1;
    
    _effectiveQueue.removeAt(index);
    await _playlist.removeAt(index);
    
    _updateQueueNotifier();
    
    if (index == currentIndex) {
      // If we removed the current song, it should automatically skip to next 
      // because just_audio handles removal of current source by skipping.
    }
    
    _cacheSurroundingSongs(_player.currentIndex ?? 0, _effectiveQueue);
  }

  void dispose() {
    _player.dispose();
    shuffleNotifier.dispose();
  }
}


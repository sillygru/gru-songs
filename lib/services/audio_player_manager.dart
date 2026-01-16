import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:flutter/painting.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/shuffle_config.dart';
import 'cache_service.dart';
import 'api_service.dart';
import 'stats_service.dart';
import 'storage_service.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  final StatsService _statsService;
  final StorageService _storageService;
  final String? _username;
  
  late ConcatenatingAudioSource _playlist;
  List<QueueItem> _originalQueue = [];
  List<QueueItem> _effectiveQueue = [];
  
  // User data for weighting
  List<String> _favorites = [];
  List<String> _suggestLess = [];
  
  // Shuffle state
  ShuffleState _shuffleState = const ShuffleState();
  
  // Stats tracking state
  String? _currentSongFilename;
  DateTime? _playStartTime;
  bool _isCompleting = false;
  
  // New stats counters
  double _foregroundDuration = 0.0;
  double _backgroundDuration = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
  final ValueNotifier<ShuffleState> shuffleStateNotifier = ValueNotifier(const ShuffleState());
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);

  AudioPlayerManager(this._apiService, this._statsService, this._storageService, this._username) {
    WidgetsBinding.instance.addObserver(this);
    _initStatsListeners();
    _initPersistence();
  }
  
  AudioPlayer get player => _player;

  void setUserData({List<String>? favorites, List<String>? suggestLess}) {
    if (favorites != null) _favorites = favorites;
    if (suggestLess != null) _suggestLess = suggestLess;
  }

  void updateShuffleConfig(ShuffleConfig config) {
    _shuffleState = _shuffleState.copyWith(config: config);
    shuffleStateNotifier.value = _shuffleState;
    shuffleNotifier.value = config.enabled;
    _saveShuffleState();
    
    // If shuffle is currently enabled, re-apply it to update the remaining queue weights
    if (config.enabled && _player.currentIndex != null) {
      _applyShuffle(_player.currentIndex!);
    }
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue, bool startPlaying = true}) async {
    await _player.setShuffleModeEnabled(false);
    if (contextQueue != null) {
      _originalQueue = contextQueue.map((s) => QueueItem(song: s)).toList();
    } else if (_originalQueue.isEmpty) {
      _originalQueue = [QueueItem(song: song)];
    }

    int originalIdx = _originalQueue.indexWhere((item) => item.song.filename == song.filename);
    if (originalIdx == -1) {
      _originalQueue.insert(0, QueueItem(song: song));
      originalIdx = 0;
    }

    final selectedItem = _originalQueue[originalIdx];

    if (_shuffleState.config.enabled) {
      final otherItems = List<QueueItem>.from(_originalQueue)..removeAt(originalIdx);
      final shuffledOthers = _weightedShuffle(otherItems, lastItem: selectedItem);
      
      _effectiveQueue = [selectedItem, ...shuffledOthers];
      await _rebuildPlaylist(initialIndex: 0, startPlaying: startPlaying);
    } else {
      _effectiveQueue = List.from(_originalQueue);
      await _rebuildPlaylist(initialIndex: originalIdx, startPlaying: startPlaying);
    }
    _savePlaybackState();
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
         _isCompleting = true;
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
                if (!_isCompleting) {
                    _flushStats(eventType: 'skip');
                }
            }
            
            // Set new song
            if (_currentSongFilename != newFilename) {
                _isCompleting = false;
                _currentSongFilename = newFilename;
                _foregroundDuration = 0.0;
                _backgroundDuration = 0.0;
                _playStartTime = _player.playing ? DateTime.now() : null;
                _savePlaybackState();
                
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

  Future<void> _initPersistence() async {
    if (_username == null) return;

    // 1. Load local cache
    final localStateData = await _storageService.loadShuffleState(_username!);
    if (localStateData != null) {
      _shuffleState = ShuffleState.fromJson(localStateData);
      shuffleNotifier.value = _shuffleState.config.enabled;
      shuffleStateNotifier.value = _shuffleState;
    }

    // 2. Fetch from backend (async)
    _syncShuffleState();
  }

  Future<void> _syncShuffleState() async {
    if (_username == null) return;
    
    final summary = await _statsService.getStatsSummary(_username!);
    if (summary != null && summary['shuffle_state'] != null) {
      final remoteState = ShuffleState.fromJson(summary['shuffle_state']);
      
      // Timestamp-aware merge of history
      final mergedMap = <String, HistoryEntry>{};
      
      // Add local first
      for (var entry in _shuffleState.history) {
        mergedMap[entry.filename] = entry;
      }
      
      // Merge remote (only if remote has a newer timestamp for the same song)
      for (var entry in remoteState.history) {
        if (!mergedMap.containsKey(entry.filename) || entry.timestamp > mergedMap[entry.filename]!.timestamp) {
          mergedMap[entry.filename] = entry;
        }
      }
      
      final mergedHistory = mergedMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      final limitedHistory = mergedHistory.take(_shuffleState.config.historyLimit).toList();

      _shuffleState = _shuffleState.copyWith(
        config: remoteState.config.copyWith(enabled: _shuffleState.config.enabled),
        history: limitedHistory,
      );
      shuffleStateNotifier.value = _shuffleState;
      await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
    }
  }

  Future<void> _saveShuffleState() async {
    if (_username == null) return;
    await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
    // Background sync to backend
    _statsService.updateShuffleState(_username!, _shuffleState.toJson());
  }

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final currentIndex = _player.currentIndex;
    final currentSong = (currentIndex != null && currentIndex < _effectiveQueue.length) 
        ? _effectiveQueue[currentIndex].song 
        : null;
    
    if (currentSong != null) {
      await prefs.setString('last_song_filename', currentSong.filename);
    }
    
    await prefs.setString('last_effective_queue', jsonEncode(_effectiveQueue.map((e) => e.toJson()).toList()));
    await prefs.setString('last_original_queue', jsonEncode(_originalQueue.map((e) => e.toJson()).toList()));
    await prefs.setInt('last_position_ms', _player.position.inMilliseconds);
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

        // Update local shuffle history
        if (eventType == 'complete' || finalDuration > 30) {
           _addToShuffleHistory(_currentSongFilename!);
        }
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

  void _addToShuffleHistory(String filename) {
    final history = List<HistoryEntry>.from(_shuffleState.history);
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    // Remove existing entry for this song
    history.removeWhere((e) => e.filename == filename);
    
    // Add new timestamped entry at the top
    history.insert(0, HistoryEntry(filename: filename, timestamp: timestamp));
    
    if (history.length > _shuffleState.config.historyLimit) {
      history.removeRange(_shuffleState.config.historyLimit, history.length);
    }
    
    _shuffleState = _shuffleState.copyWith(history: history);
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If playing, attribute time spent in previous state
    if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = DateTime.now(); // Reset start time for the new state
    }
    
    // Flush stats when app is hidden or closed to ensure no data loss
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _flushStats(eventType: 'listen');
      _savePlaybackState();
      
      // Clear image cache to save RAM while in background
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    
    _appLifecycleState = state;
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    await _player.setShuffleModeEnabled(false);
    
    // Attempt to restore saved state
    final prefs = await SharedPreferences.getInstance();
    final savedEffectiveQueueJson = prefs.getString('last_effective_queue');
    final savedOriginalQueueJson = prefs.getString('last_original_queue');
    final savedPositionMs = prefs.getInt('last_position_ms') ?? 0;
    final lastSongFilename = prefs.getString('last_song_filename');

    if (savedEffectiveQueueJson != null && savedOriginalQueueJson != null) {
      try {
        final List<dynamic> effJson = jsonDecode(savedEffectiveQueueJson);
        final List<dynamic> origJson = jsonDecode(savedOriginalQueueJson);
        
        _effectiveQueue = effJson.map((j) => QueueItem.fromJson(j)).toList();
        _originalQueue = origJson.map((j) => QueueItem.fromJson(j)).toList();
        
        int initialIndex = 0;
        if (lastSongFilename != null) {
          initialIndex = _effectiveQueue.indexWhere((item) => item.song.filename == lastSongFilename);
          if (initialIndex == -1) initialIndex = 0;
        }

        await _rebuildPlaylist(
          initialIndex: initialIndex, 
          startPlaying: false, 
          initialPosition: Duration(milliseconds: savedPositionMs)
        );
        return;
      } catch (e) {
        debugPrint("Error restoring saved queue: $e");
      }
    }

    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _effectiveQueue = List.from(_originalQueue);
    
    try {
      int initialIndex = 0;
      if (autoSelect && songs.isNotEmpty) {
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

      await _rebuildPlaylist(initialIndex: initialIndex, startPlaying: false);
      
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
        title: song.title,
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
          'androidStopForegroundOnPause': true,
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
    
    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: true),
    );
    shuffleNotifier.value = true;
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();

    final randomIdx = Random().nextInt(songs.length);
    await playSong(songs[randomIdx], contextQueue: songs, startPlaying: true);
    _savePlaybackState();
  }

  Future<void> toggleShuffle() async {
    final isShuffle = !shuffleNotifier.value;
    shuffleNotifier.value = isShuffle;
    
    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: isShuffle),
    );
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();
    
    final currentIndex = _player.currentIndex ?? 0;
    if (isShuffle) {
      _applyShuffle(currentIndex);
    } else {
      _applyLinear(currentIndex);
    }
    _savePlaybackState();
  }

  void _applyShuffle(int currentIndex) {
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) currentIndex = 0;
    
    final currentItem = _effectiveQueue[currentIndex];
    
    // Split into priority and non-priority (excluding current)
    final otherItems = <QueueItem>[];
    for (int i = 0; i < _effectiveQueue.length; i++) {
      if (i == currentIndex) continue;
      otherItems.add(_effectiveQueue[i]);
    }
    
    final priorityItems = otherItems.where((item) => item.isPriority).toList();
    final normalItems = otherItems.where((item) => !item.isPriority).toList();
    
    // Weighted shuffle for normal items
    final shuffledNormal = _weightedShuffle(normalItems, lastItem: currentItem);
    
    _effectiveQueue = [
      currentItem,
      ...priorityItems,
      ...shuffledNormal,
    ];
    
    _rebuildPlaylist(initialIndex: 0, startPlaying: _player.playing);
    _savePlaybackState();
  }

  List<QueueItem> _weightedShuffle(List<QueueItem> items, {QueueItem? lastItem}) {
    if (items.isEmpty) return [];
    
    final result = <QueueItem>[];
    final remaining = List<QueueItem>.from(items);
    QueueItem? prev = lastItem;

    while (remaining.isNotEmpty) {
      final weights = remaining.map((item) => _calculateWeight(item, prev)).toList();
      final totalWeight = weights.fold(0.0, (a, b) => a + b);
      
      if (totalWeight <= 0) {
        remaining.shuffle();
        result.addAll(remaining);
        break;
      }

      double randomValue = Random().nextDouble() * totalWeight;
      int selectedIdx = -1;
      double cumulative = 0.0;
      for (int i = 0; i < weights.length; i++) {
        cumulative += weights[i];
        if (randomValue <= cumulative) {
          selectedIdx = i;
          break;
        }
      }
      
      if (selectedIdx == -1) selectedIdx = remaining.length - 1;
      
      final selected = remaining.removeAt(selectedIdx);
      result.add(selected);
      prev = selected;
    }
    
    return result;
  }

  double _calculateWeight(QueueItem item, QueueItem? prev) {
    double weight = 1.0;
    final song = item.song;
    final config = _shuffleState.config;

    // 1. Anti-repeat (Recent History)
    if (config.antiRepeatEnabled && _shuffleState.history.isNotEmpty) {
      int historyIndex = _shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1) {
        double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
        weight *= (1.0 - max(0.0, reduction));
      }
    }

    // 2. Streak Breaker (Same Artist/Album)
    if (config.streakBreakerEnabled && prev != null) {
      final prevSong = prev.song;
      
      if (song.artist != 'Unknown Artist' && prevSong.artist != 'Unknown Artist') {
        if (song.artist == prevSong.artist) {
          weight *= 0.5;
        }
      }
      
      if (song.album != 'Unknown Album' && prevSong.album != 'Unknown Album') {
        if (song.album == prevSong.album) {
          weight *= 0.7;
        }
      }
    }

    // 3. User Preferences
    if (_favorites.contains(song.filename)) {
      weight *= config.favoriteMultiplier;
    }
    
    if (_suggestLess.contains(song.filename)) {
      weight *= config.suggestLessMultiplier;
    }

    return max(0.001, weight);
  }

  void _applyLinear(int currentIndex) {
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) currentIndex = 0;
    
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
    _rebuildPlaylist(initialIndex: newIndex, startPlaying: _player.playing);
    _savePlaybackState();
  }

  Future<void> _rebuildPlaylist({int? initialIndex, bool startPlaying = true, Duration? initialPosition}) async {
    if (_effectiveQueue.isEmpty) return;
    
    final position = initialPosition ?? _player.position;
    final targetIndex = initialIndex ?? _player.currentIndex ?? 0;
    
    final sources = await Future.wait(_effectiveQueue.map((item) => _createAudioSource(item)));
    
    _playlist = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );
    await _player.setAudioSource(
      _playlist,
      initialIndex: targetIndex,
      initialPosition: (targetIndex == (_player.currentIndex ?? -1) || initialPosition != null) ? position : Duration.zero,
    );
    
    if (startPlaying) await _player.play();
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
    _savePlaybackState();
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
    _savePlaybackState();
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
    _savePlaybackState();
  }

  void dispose() {
    _player.dispose();
    shuffleNotifier.dispose();
  }
}


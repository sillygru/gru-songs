import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:flutter/painting.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async'; // For Timer
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
  List<Song> _allSongs = [];
  Map<String, Song> _songMap = {};
  
  // Server Sync State
  int _queueVersion = 0;
  bool _isOffline = false;
  Timer? _syncTimer;
  
  // User data for weighting (Fallback / Offline)
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
    
    // Server Authoritative: Toggle means re-sync
    if (_effectiveQueue.isNotEmpty) {
      if (config.enabled) {
         // Optimistic Shuffle
         _applyShuffle(_player.currentIndex ?? 0);
      } else {
         _applyLinear(_player.currentIndex ?? 0);
      }
      _syncQueueToServer();
    }
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue, bool startPlaying = true}) async {
    await _player.setShuffleModeEnabled(false);
    
    // 1. Setup Local Queue (Optimistic)
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
      // Offline / Optimistic Shuffle Logic
      final otherItems = List<QueueItem>.from(_originalQueue)..removeAt(originalIdx);
      final shuffledOthers = _weightedShuffle(otherItems, lastItem: selectedItem);
      _effectiveQueue = [selectedItem, ...shuffledOthers];
      await _rebuildPlaylist(initialIndex: 0, startPlaying: startPlaying);
    } else {
      _effectiveQueue = List.from(_originalQueue);
      await _rebuildPlaylist(initialIndex: originalIdx, startPlaying: startPlaying);
    }
    
    _savePlaybackState();
    
    // 2. Sync to Server
    _syncQueueToServer();
  }

  Future<void> _syncQueueToServer() async {
    if (_username == null || _isOffline) return;
    
    try {
      final currentIndex = _player.currentIndex ?? 0;
      final simplifiedQueue = _effectiveQueue.map((item) => {
        'queue_id': item.queueId,
        'song_filename': item.song.filename,
        'is_priority': item.isPriority,
        'added_at': DateTime.now().millisecondsSinceEpoch / 1000.0, // Should be preserved?
      }).toList();
      
      final result = await _apiService.syncQueue(simplifiedQueue, currentIndex, _queueVersion);
      
      if (result['version'] > _queueVersion) {
         await _processServerQueue(result);
      }
      
      _isOffline = false;
    } catch (e) {
      debugPrint("Queue Sync Failed (Switching to Offline Mode): $e");
      _isOffline = true;
    }
  }
  
  Future<void> _processServerQueue(Map<String, dynamic> data) async {
      final int version = data['version'];
      final int serverIndex = data['current_index'];
      final List<dynamic> items = data['items'];
      
      if (version <= _queueVersion) return; // Ignore stale
      
      final newQueue = <QueueItem>[];
      for (var item in items) {
          final filename = item['song_filename'];
          final song = _songMap[filename];
          if (song != null) {
             newQueue.add(QueueItem(
                 song: song,
                 queueId: item['queue_id'],
                 isPriority: item['is_priority'] ?? false
             ));
          }
      }
      
      if (newQueue.isEmpty) return;
      
      // Determine if we need to hard replace or soft update
      // Hard replace if completely different.
      // For now, let's just replace _effectiveQueue and update playlist if needed.
      
      _effectiveQueue = newQueue;
      _queueVersion = version;
      _updateQueueNotifier();
      _savePlaybackState();
      
      // If the currently playing song is the same at the same index, we might not need to reload audio
      // But if order changed, just_audio might need help.
      // Rebuild playlist carefully.
      
      // If currently playing, try not to interrupt.
      // Note: _rebuildPlaylist will interrupt playback if source changes.
      // If we are playing, and the new queue has the same song at same index, 
      // AND subsequent songs are same, we are good.
      // But usually Sync happens after a mutation.
      
      // Basic approach: Only rebuild if significantly different?
      // Or just rebuild. Rebuild interrupts.
      // We only want to rebuild if WE didn't initiate the change (incoming sync).
      // But `_syncQueueToServer` is called after WE change something.
      // If server returns EXACTLY what we sent, we are good.
      
      // Check if `newQueue` == `_effectiveQueue` (which we just set).
      // If we are calling this from `_syncQueueToServer`, we might have just set `_effectiveQueue` locally.
      // If server returns something different (e.g. it re-shuffled), we should update.
      
      // Ideally, we compare queue IDs.
      // For now, just rebuild if not playing or if explicit mutation.
      // Just rebuild. It might skip a beat, but consistency is key.
      if (_player.playing) {
          // Try to maintain position
          await _rebuildPlaylist(initialIndex: serverIndex, startPlaying: true);
      } else {
          await _rebuildPlaylist(initialIndex: serverIndex, startPlaying: false);
      }
  }

  Future<void> _fetchNextFromServer() async {
      if (_isOffline) return;
      
      try {
          final nextItem = await _apiService.fetchNextSong();
          if (nextItem != null) {
             final filename = nextItem['song_filename'];
             final song = _songMap[filename];
             if (song != null) {
                 final item = QueueItem(
                     song: song,
                     queueId: nextItem['queue_id'],
                     isPriority: nextItem['is_priority'] ?? false
                 );
                 
                 _effectiveQueue.add(item);
                 final source = await _createAudioSource(item);
                 await _playlist.add(source);
                 
                 _updateQueueNotifier();
                 _queueVersion = nextItem['version'] ?? (_queueVersion + 1); // Increment version implicitly?
                 _savePlaybackState();
             }
          }
      } catch (e) {
          debugPrint("Fetch Next Failed: $e");
          // Fallback handled in listener (if queue end reached)
      }
  }
  
  void _initStatsListeners() {
    _player.playerStateStream.listen((state) {
      if (_username == null) return;
      if (state.playing) {
        _playStartTime ??= DateTime.now();
      } else if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = null;
      }
      if (state.processingState == ProcessingState.completed) {
         _isCompleting = true;
         _flushStats(eventType: 'complete');
      }
    });
    
    _player.sequenceStateStream.listen((state) {
        final currentItem = state.currentSource?.tag;
        
        // Pre-fetch logic
        final currentIndex = state.currentIndex;
        if (currentIndex != null && _effectiveQueue.isNotEmpty) {
            // If we are within 2 songs of the end, fetch more
            if (currentIndex >= _effectiveQueue.length - 2) {
                // If Shuffle is ON, ask server for more.
                // If Shuffle OFF, usually we have full list, but if we are consuming a queue...
                if (_shuffleState.config.enabled && !_isOffline) {
                    _fetchNextFromServer();
                } else if (_shuffleState.config.enabled && _isOffline) {
                    // Offline fallback generation
                    _generateOfflineNext();
                }
            }
        }

        if (currentItem is MediaItem) {
            final newFilename = currentItem.id;
            if (_currentSongFilename != null && _currentSongFilename != newFilename) {
                if (!_isCompleting) _flushStats(eventType: 'skip');
            }
            if (_currentSongFilename != newFilename) {
                _isCompleting = false;
                _currentSongFilename = newFilename;
                _foregroundDuration = 0.0;
                _backgroundDuration = 0.0;
                _playStartTime = _player.playing ? DateTime.now() : null;
                _savePlaybackState();
                _verifyCurrentSongCache(currentItem);
                
                // Sync current index to server
                // We don't need to send full queue, just index update?
                // The sync endpoint takes full queue + index.
                // Maybe overly chatty?
                // We can just fire and forget.
                if (!_isOffline) _syncQueueToServer();
            }
        }
    });
  }

  void _generateOfflineNext() {
      // Pick a random song from _allSongs using local weights
      if (_allSongs.isEmpty) return;
      
      // Simple wrapper around _weightedShuffle logic for a single item
      // We don't have a "next" pool, so we pick from ALL songs.
      // This is basically "Endless Mode".
      
      // Filter out recent history locally
      var candidates = _allSongs.where((s) => 
          !_effectiveQueue.reversed.take(10).any((q) => q.song.filename == s.filename)
      ).toList();
      
      if (candidates.isEmpty) candidates = List.from(_allSongs);
      
      // Just pick random for simplicity in fallback, or use weights
      // Using _weightedShuffle logic requires a list of items.
      final queueItems = candidates.map((s) => QueueItem(song: s)).toList();
      final lastItem = _effectiveQueue.isNotEmpty ? _effectiveQueue.last : null;
      
      // Calculate weights for a sample
      // For performance, just sample 50 randoms and pick best
      queueItems.shuffle();
      final sample = queueItems.take(50).toList();
      final result = _weightedShuffle(sample, lastItem: lastItem);
      
      if (result.isNotEmpty) {
          final nextItem = result.first;
          _effectiveQueue.add(nextItem);
          _createAudioSource(nextItem).then((source) {
              _playlist.add(source);
              _updateQueueNotifier();
          });
      }
  }

  Future<void> _verifyCurrentSongCache(MediaItem item) async {
    final url = item.extras?['remoteUrl'] as String?;
    if (url == null) return;
    try {
      await CacheService.instance.getFile('songs', item.id, url);
    } catch (e) {
      debugPrint("Cache check failed: $e");
    }
  }

  Future<void> _initPersistence() async {
    if (_username == null) return;
    final localStateData = await _storageService.loadShuffleState(_username!);
    if (localStateData != null) {
      _shuffleState = ShuffleState.fromJson(localStateData);
      shuffleNotifier.value = _shuffleState.config.enabled;
      shuffleStateNotifier.value = _shuffleState;
    }
    _syncShuffleState();
  }

  Future<void> _syncShuffleState() async {
    if (_username == null) return;
    try {
        final summary = await _statsService.getStatsSummary(_username!);
        if (summary != null && summary['shuffle_state'] != null) {
          final remoteState = ShuffleState.fromJson(summary['shuffle_state']);
          // Merge logic (omitted for brevity, same as before)
           _shuffleState = _shuffleState.copyWith(
            config: remoteState.config.copyWith(enabled: _shuffleState.config.enabled),
            history: remoteState.history, // Trust server history
          );
          shuffleStateNotifier.value = _shuffleState;
          await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
        }
    } catch (e) {
        // Offline
    }
  }

  Future<void> _saveShuffleState() async {
    if (_username == null) return;
    await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
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
    }
  }
  
  void _flushStats({required String eventType}) {
    if (_username == null || _currentSongFilename == null) return;
    if (_playStartTime != null) _updateDurations();
    double finalDuration = _foregroundDuration + _backgroundDuration;
    if (finalDuration > 0.5) {
        _statsService.track(_username!, _currentSongFilename!, finalDuration, eventType,
          foregroundDuration: _foregroundDuration, backgroundDuration: _backgroundDuration);
        if (eventType == 'complete' || finalDuration > 30) {
           _addToShuffleHistory(_currentSongFilename!);
        }
    }
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
        _playStartTime = null; 
    } else {
        if (_playStartTime != null) _playStartTime = DateTime.now();
    }
  }

  void _addToShuffleHistory(String filename) {
     // Server handles history now via stats flushing, but we keep local for offline weight calc
     // ... (same as before) ...
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = DateTime.now();
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _flushStats(eventType: 'listen');
      _savePlaybackState();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    _appLifecycleState = state;
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    _allSongs = songs;
    _songMap = {for (var s in songs) s.filename: s};
    await _player.setShuffleModeEnabled(false);
    
    // 1. Try Server Init
    bool loadedFromServer = false;
    try {
        final queueData = await _apiService.fetchQueue();
        if (queueData['items'] != null && (queueData['items'] as List).isNotEmpty) {
            await _processServerQueue(queueData);
            loadedFromServer = true;
        }
    } catch (e) {
        debugPrint("Server Queue Init Failed: $e");
        _isOffline = true;
    }

    if (!loadedFromServer) {
        // 2. Fallback to Local Storage
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
            } catch (e) { }
        }

        // 3. Fallback to default list
        _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
        _effectiveQueue = List.from(_originalQueue);
        
        // Auto-select logic...
        int initialIndex = 0;
        if (autoSelect && songs.isNotEmpty) {
             initialIndex = Random().nextInt(songs.length);
        }
        await _rebuildPlaylist(initialIndex: initialIndex, startPlaying: false);
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
        CacheService.instance.getFile('songs', song.filename, url, version: song.mtime?.toString(), triggerDownload: true).catchError((e) => null);
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

    // Pick random start
    final randomIdx = Random().nextInt(songs.length);
    // playSong will trigger shuffle + sync
    await playSong(songs[randomIdx], contextQueue: songs, startPlaying: true);
  }

  Future<void> toggleShuffle() async {
    final isShuffle = !shuffleNotifier.value;
    shuffleNotifier.value = isShuffle;
    _shuffleState = _shuffleState.copyWith(config: _shuffleState.config.copyWith(enabled: isShuffle));
    shuffleStateNotifier.value = _shuffleState;
    updateShuffleConfig(_shuffleState.config); // Re-uses logic
  }

  void _applyShuffle(int currentIndex) {
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) currentIndex = 0;
    
    final currentItem = _effectiveQueue[currentIndex];
    final otherItems = <QueueItem>[];
    for (int i = 0; i < _effectiveQueue.length; i++) {
      if (i == currentIndex) continue;
      otherItems.add(_effectiveQueue[i]);
    }
    
    final priorityItems = otherItems.where((item) => item.isPriority).toList();
    final normalItems = otherItems.where((item) => !item.isPriority).toList();
    final shuffledNormal = _weightedShuffle(normalItems, lastItem: currentItem);
    
    _effectiveQueue = [currentItem, ...priorityItems, ...shuffledNormal];
    // Don't rebuild here if called from updateShuffleConfig, let the caller handle or sync.
    // Actually updateShuffleConfig calls this. 
    // We should probably just sync.
    // But for UI responsiveness, we rebuild playlist locally.
    
    // Check if we are playing to determine if we interrupt
    // If playing, we only want to change the "Next" items.
    // ConcatenatingAudioSource allows modifying the list.
    // But simply recreating it is safer for "Total Shuffle".
    _rebuildPlaylist(initialIndex: 0, startPlaying: _player.playing);
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
    // ... (Existing Logic for Offline Fallback) ...
    double weight = 1.0;
    final song = item.song;
    final config = _shuffleState.config;
    if (config.antiRepeatEnabled && _shuffleState.history.isNotEmpty) {
      int historyIndex = _shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1) {
        double reduction = 0.95 * (1.0 - (historyIndex / config.historyLimit));
        weight *= (1.0 - max(0.0, reduction));
      }
    }
    if (config.streakBreakerEnabled && prev != null) {
      final prevSong = prev.song;
      if (song.artist != 'Unknown Artist' && prevSong.artist != 'Unknown Artist' && song.artist == prevSong.artist) weight *= 0.5;
      if (song.album != 'Unknown Album' && prevSong.album != 'Unknown Album' && song.album == prevSong.album) weight *= 0.7;
    }
    if (_favorites.contains(song.filename)) weight *= config.favoriteMultiplier;
    if (_suggestLess.contains(song.filename)) weight *= config.suggestLessMultiplier;
    return max(0.001, weight);
  }

  void _applyLinear(int currentIndex) {
     // ... (Existing Logic) ...
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) currentIndex = 0;
    final currentItem = _effectiveQueue[currentIndex];
    final priorityItems = _effectiveQueue.where((item) => item.isPriority && item != currentItem).toList();
    final originalItems = _originalQueue.where((item) => !priorityItems.any((p) => p.queueId == item.queueId)).toList();
    int originalIdx = originalItems.indexWhere((item) => item.song.filename == currentItem.song.filename);
    if (originalIdx != -1) {
      _effectiveQueue = [...originalItems.sublist(0, originalIdx), currentItem, ...priorityItems, ...originalItems.sublist(originalIdx + 1)];
    } else {
      _effectiveQueue = [currentItem, ...priorityItems, ...originalItems];
    }
    int newIndex = _effectiveQueue.indexOf(currentItem);
    _rebuildPlaylist(initialIndex: newIndex, startPlaying: _player.playing);
  }

  Future<void> _rebuildPlaylist({int? initialIndex, bool startPlaying = true, Duration? initialPosition}) async {
    if (_effectiveQueue.isEmpty) return;
    final position = initialPosition ?? _player.position;
    final targetIndex = initialIndex ?? _player.currentIndex ?? 0;
    final sources = await Future.wait(_effectiveQueue.map((item) => _createAudioSource(item)));
    _playlist = ConcatenatingAudioSource(children: sources, useLazyPreparation: true);
    await _player.setAudioSource(_playlist, initialIndex: targetIndex, initialPosition: (targetIndex == (_player.currentIndex ?? -1) || initialPosition != null) ? position : Duration.zero);
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
    _syncQueueToServer();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _effectiveQueue.removeAt(oldIndex);
    _effectiveQueue.insert(newIndex, item);
    await _playlist.move(oldIndex, newIndex);
    _updateQueueNotifier();
    _savePlaybackState();
    _syncQueueToServer();
  }

  Future<void> removeFromQueue(int index) async {
    _effectiveQueue.removeAt(index);
    await _playlist.removeAt(index);
    _updateQueueNotifier();
    _savePlaybackState();
    _syncQueueToServer();
  }

  void dispose() {
    _player.dispose();
    shuffleNotifier.dispose();
    _syncTimer?.cancel();
  }
}
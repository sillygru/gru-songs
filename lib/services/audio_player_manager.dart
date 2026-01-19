import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async'; // For Timer
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/shuffle_config.dart';
import 'api_service.dart';
import 'stats_service.dart';
import 'storage_service.dart';
import 'database_service.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  final StatsService _statsService;
  final StorageService _storageService;
  final String? _username;

  List<QueueItem> _originalQueue = [];
  List<QueueItem> _effectiveQueue = [];
  List<Song> _allSongs = [];
  Map<String, Song> _songMap = {};

  // Server Sync State
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
  final ValueNotifier<ShuffleState> shuffleStateNotifier =
      ValueNotifier(const ShuffleState());
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);

  AudioPlayerManager(this._apiService, this._statsService, this._storageService,
      this._username) {
    WidgetsBinding.instance.addObserver(this);
    if (_username != null) {
      DatabaseService.instance.initForUser(_username!);
    }
    _initStatsListeners();
    _initPersistence();
  }

  AudioPlayer get player => _player;

  void setUserData({List<String>? favorites, List<String>? suggestLess}) {
    if (favorites != null) _favorites = favorites;
    if (suggestLess != null) _suggestLess = suggestLess;
  }

  Future<void> updateShuffleConfig(ShuffleConfig config) async {
    _shuffleState = _shuffleState.copyWith(config: config);
    shuffleStateNotifier.value = _shuffleState;
    shuffleNotifier.value = config.enabled;
    _saveShuffleState();

    if (_effectiveQueue.isNotEmpty) {
      if (config.enabled) {
        await _applyShuffle(_player.currentIndex ?? 0);
      } else {
        _applyLinear(_player.currentIndex ?? 0);
      }
    }
  }

  Future<void> updateShuffleState(ShuffleState newState) async {
    _shuffleState = newState;
    shuffleStateNotifier.value = _shuffleState;
    shuffleNotifier.value = newState.config.enabled;
    _saveShuffleState();
  }

  Future<void> playSong(Song song,
      {List<Song>? contextQueue, bool startPlaying = true}) async {
    await _player.setShuffleModeEnabled(false);

    // 1. Setup Local Queue (Optimistic)
    if (contextQueue != null) {
      _originalQueue = contextQueue.map((s) => QueueItem(song: s)).toList();
    } else if (_originalQueue.isEmpty) {
      _originalQueue = [QueueItem(song: song)];
    }

    int originalIdx = _originalQueue
        .indexWhere((item) => item.song.filename == song.filename);
    if (originalIdx == -1) {
      _originalQueue.insert(0, QueueItem(song: song));
      originalIdx = 0;
    }

    final selectedItem = _originalQueue[originalIdx];

    if (_shuffleState.config.enabled) {
      final otherItems = List<QueueItem>.from(_originalQueue)
        ..removeAt(originalIdx);
      final shuffledOthers =
          await _weightedShuffle(otherItems, lastItem: selectedItem);
      _effectiveQueue = [selectedItem, ...shuffledOthers];
      await _rebuildQueue(initialIndex: 0, startPlaying: startPlaying);
    } else {
      _effectiveQueue = List.from(_originalQueue);
      await _rebuildQueue(
          initialIndex: originalIdx, startPlaying: startPlaying);
    }

    _savePlaybackState();
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
        if (currentIndex >= _effectiveQueue.length - 2) {
          if (_shuffleState.config.enabled) {
            _generateOfflineNext();
          }
        }
      }

      if (currentItem is MediaItem) {
        final newFilename = currentItem.id;
        if (_currentSongFilename != null &&
            _currentSongFilename != newFilename) {
          if (!_isCompleting) _flushStats(eventType: 'skip');
        }
        if (_currentSongFilename != newFilename) {
          _isCompleting = false;
          _currentSongFilename = newFilename;
          _foregroundDuration = 0.0;
          _backgroundDuration = 0.0;
          _playStartTime = _player.playing ? DateTime.now() : null;
          _savePlaybackState();
        }
      }
    });
  }

  void _generateOfflineNext() async {
    // Pick a random song from _allSongs using local weights
    if (_allSongs.isEmpty) return;

    var candidates = _allSongs
        .where((s) => !_effectiveQueue.reversed
            .take(10)
            .any((q) => q.song.filename == s.filename))
        .toList();

    if (candidates.isEmpty) candidates = List.from(_allSongs);

    final queueItems = candidates.map((s) => QueueItem(song: s)).toList();
    final lastItem = _effectiveQueue.isNotEmpty ? _effectiveQueue.last : null;

    queueItems.shuffle();
    final sample = queueItems.take(50).toList();
    final result = await _weightedShuffle(sample, lastItem: lastItem);

    if (result.isNotEmpty) {
      final nextItem = result.first;
      _effectiveQueue.add(nextItem);
      _createAudioSource(nextItem).then((source) {
        _player.addAudioSource(source);
        _updateQueueNotifier();
      });
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
    syncShuffleState();

    // Start periodic sync of all user data every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _syncAllUserDataPeriodically();
    });
  }

  Future<void> _syncAllUserDataPeriodically() async {
    if (_username == null) return;
    try {
      // Trigger comprehensive sync through the provider
      // We'll make an API call to sync all user data
      final response = await _apiService.client.get(
        Uri.parse('${ApiService.baseUrl}/user/data'),
        headers: {'x-username': _username!},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverFavs = List<String>.from(data['favorites'] ?? []);
        final serverSuggestLess = List<String>.from(data['suggestLess'] ?? []);
        final serverShuffleState = data['shuffleState'];

        // Update local database
        await _updateLocalUserData(serverFavs, serverSuggestLess);

        // Update shuffle state from server if available
        if (serverShuffleState != null) {
          final updatedShuffleState = ShuffleState.fromJson(serverShuffleState);
          await updateShuffleState(updatedShuffleState);
        }
      }
    } catch (e) {
      debugPrint('Periodic user data sync failed: $e');
    }
  }

  Future<void> _updateLocalUserData(List<String> favorites, List<String> suggestLess) async {
    // Update local database with server data
    final currentFavs = await DatabaseService.instance.getFavorites();
    final currentSuggestLess = await DatabaseService.instance.getSuggestLess();

    // Remove items that are no longer in the lists
    for (final filename in currentFavs) {
      if (!favorites.contains(filename)) {
        await DatabaseService.instance.removeFavorite(filename);
      }
    }

    for (final filename in currentSuggestLess) {
      if (!suggestLess.contains(filename)) {
        await DatabaseService.instance.removeSuggestLess(filename);
      }
    }

    // Add new items
    for (final filename in favorites) {
      if (!currentFavs.contains(filename)) {
        await DatabaseService.instance.addFavorite(filename);
      }
    }

    for (final filename in suggestLess) {
      if (!currentSuggestLess.contains(filename)) {
        await DatabaseService.instance.addSuggestLess(filename);
      }
    }
  }

  Future<ShuffleState?> syncShuffleState() async {
    if (_username == null) return null;
    try {
      // Prioritize local final_stats.json which is synced/mirrored by DatabaseService
      final summary = await _statsService.getStatsSummary(_username!);
      if (summary != null && summary['shuffle_state'] != null) {
        final remoteState = ShuffleState.fromJson(summary['shuffle_state']);

        // Merge logic: Personality and History come from synced summary.
        _shuffleState = _shuffleState.copyWith(
          config: remoteState.config
              .copyWith(enabled: _shuffleState.config.enabled),
          history: remoteState.history,
        );

        shuffleStateNotifier.value = _shuffleState;
        await _storageService.saveShuffleState(
            _username!, _shuffleState.toJson());
        return _shuffleState;
      }
    } catch (e) {
      debugPrint("Shuffle Sync Failed: $e");
    }
    return null;
  }

  Future<void> _saveShuffleState() async {
    if (_username == null) return;
    await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
    _statsService.updateShuffleState(_username!, _shuffleState.toJson());
  }

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final currentIndex = _player.currentIndex;
    final currentSong =
        (currentIndex != null && currentIndex < _effectiveQueue.length)
            ? _effectiveQueue[currentIndex].song
            : null;

    if (currentSong != null) {
      await prefs.setString('last_song_filename', currentSong.filename);
    }
    await prefs.setString('last_effective_queue',
        jsonEncode(_effectiveQueue.map((e) => e.toJson()).toList()));
    await prefs.setString('last_original_queue',
        jsonEncode(_originalQueue.map((e) => e.toJson()).toList()));
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
    
    final song = _songMap[_currentSongFilename!];
    final totalLength = (song?.duration?.inMilliseconds.toDouble() ?? 0.0) / 1000.0;
    
    double finalDuration = _foregroundDuration + _backgroundDuration;
    if (finalDuration > 0.5) {
      _statsService.track(
          _username!, _currentSongFilename!, finalDuration, eventType,
          foregroundDuration: _foregroundDuration,
          backgroundDuration: _backgroundDuration,
          totalLength: totalLength);

      // Add to local history if completed OR played for at least 5 seconds (to treat as a "seen" song for anti-repeat)
      if (eventType == 'complete' || finalDuration > 5.0) {
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
    final history = List<HistoryEntry>.from(_shuffleState.history);
    final newEntry = HistoryEntry(
        filename: filename,
        timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0);

    history.removeWhere((e) => e.filename == filename);
    history.insert(0, newEntry);

    if (history.length > _shuffleState.config.historyLimit) {
      history.removeRange(_shuffleState.config.historyLimit, history.length);
    }

    _shuffleState = _shuffleState.copyWith(history: history);
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_playStartTime != null) {
      _updateDurations();
      _playStartTime = DateTime.now();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
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

    if (_username != null) {
      await DatabaseService.instance.initForUser(_username!);
    }

    // 1. Fallback to Local Storage (Always local-first now)
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
        Duration? resumePosition;

        if (lastSongFilename != null) {
          initialIndex = _effectiveQueue
              .indexWhere((item) => item.song.filename == lastSongFilename);
          if (initialIndex != -1) {
            resumePosition = Duration(milliseconds: savedPositionMs);
          } else {
            initialIndex = 0;
          }
        }

        await _rebuildQueue(
            initialIndex: initialIndex,
            startPlaying: false,
            initialPosition: resumePosition);
        return;
      } catch (e) {
        // Ignore malformed persistence state, fallback to default
      }
    }

    // 2. Fallback to default list
    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _effectiveQueue = List.from(_originalQueue);

    // Auto-select logic...
    int initialIndex = 0;
    if (autoSelect && songs.isNotEmpty) {
      initialIndex = Random().nextInt(songs.length);
    }
    await _rebuildQueue(initialIndex: initialIndex, startPlaying: false);
  }
  Future<AudioSource> _createAudioSource(QueueItem item) async {
    final song = item.song;
    final bool isLocal = song.url.startsWith('/') || song.url.startsWith('C:\\');
    
    final Uri audioUri = isLocal ? Uri.file(song.url) : Uri.parse(_apiService.getFullUrl(song.url));
    
    Uri? artUri;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      artUri = Uri.file(song.coverUrl!);
    }

    return AudioSource.uri(
      audioUri,
      tag: MediaItem(
        id: song.filename,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        artUri: artUri,
        extras: {
          'lyricsUrl': song.lyricsUrl,
          'remoteUrl': song.url,
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
    _shuffleState = _shuffleState.copyWith(
        config: _shuffleState.config.copyWith(enabled: isShuffle));
    shuffleStateNotifier.value = _shuffleState;
    updateShuffleConfig(_shuffleState.config); // Re-uses logic
  }

  Future<void> _applyShuffle(int currentIndex) async {
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) {
      currentIndex = 0;
    }

    final currentItem = _effectiveQueue[currentIndex];
    final otherItems = <QueueItem>[];
    for (int i = 0; i < _effectiveQueue.length; i++) {
      if (i == currentIndex) continue;
      otherItems.add(_effectiveQueue[i]);
    }

    final priorityItems = otherItems.where((item) => item.isPriority).toList();
    final normalItems = otherItems.where((item) => !item.isPriority).toList();
    final shuffledNormal = await _weightedShuffle(normalItems, lastItem: currentItem);

    _effectiveQueue = [currentItem, ...priorityItems, ...shuffledNormal];
    // Don't rebuild here if called from updateShuffleConfig, let the caller handle or sync.
    // Actually updateShuffleConfig calls this.
    // We should probably just sync.
    // But for UI responsiveness, we rebuild queue locally.

    // Check if we are playing to determine if we interrupt
    // If playing, we only want to change the "Next" items.
    // ConcatenatingAudioSource allows modifying the list.
    // But simply recreating it is safer for "Total Shuffle".
    await _rebuildQueue(initialIndex: 0, startPlaying: _player.playing);
  }

  Future<List<QueueItem>> _weightedShuffle(List<QueueItem> items,
      {QueueItem? lastItem}) async {
    if (items.isEmpty) return [];
    
    // Fetch local play counts for weighting
    final playCounts = await DatabaseService.instance.getPlayCounts();
    
    final result = <QueueItem>[];
    final remaining = List<QueueItem>.from(items);
    QueueItem? prev = lastItem;
    while (remaining.isNotEmpty) {
      final weights =
          remaining.map((item) => _calculateWeight(item, prev, playCounts)).toList();
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

  double _calculateWeight(QueueItem item, QueueItem? prev, Map<String, int> playCounts) {
    double weight = 1.0;
    final song = item.song;
    final config = _shuffleState.config;
    final count = playCounts[song.filename] ?? 0;

    // --- Personality: DEFAULT ---
    if (config.personality == ShufflePersonality.defaultMode) {
      // 1. Favorites & Suggest Less
      if (_favorites.contains(song.filename)) {
        weight *= config.favoriteMultiplier;
      }
      if (_suggestLess.contains(song.filename)) {
        weight *= config.suggestLessMultiplier;
      }

      // 2. Anti-repeat (History)
      if (config.antiRepeatEnabled && _shuffleState.history.isNotEmpty) {
        int historyIndex = _shuffleState.history
            .indexWhere((e) => e.filename == song.filename);
        if (historyIndex != -1) {
          double reduction =
              0.95 * (1.0 - (historyIndex / config.historyLimit));
          weight *= (1.0 - max(0.0, reduction));
        }
      }

      // 3. Streak Breaker
      if (config.streakBreakerEnabled && prev != null) {
        final prevSong = prev.song;
        if (song.artist != 'Unknown Artist' &&
            prevSong.artist != 'Unknown Artist' &&
            song.artist == prevSong.artist) {
          weight *= 0.5;
        }
        if (song.album != 'Unknown Album' &&
            prevSong.album != 'Unknown Album' &&
            song.album == prevSong.album) {
          weight *= 0.7;
        }
      }
    }
    // --- Personality: EXPLORER ---
    else if (config.personality == ShufflePersonality.explorer) {
      if (count == 0) {
        weight *= 50.0;
      } else if (count < 5) {
        weight *= 5.0;
      } else if (count > 50) {
        weight *= 0.01;
      } else if (count > 15) {
        weight *= 0.1;
      }

      if (_favorites.contains(song.filename)) weight *= 1.1;
      if (_suggestLess.contains(song.filename)) weight *= 0.001;

      // Anti-repeat (Strong)
      if (_shuffleState.history.isNotEmpty) {
        int historyIndex = _shuffleState.history
            .indexWhere((e) => e.filename == song.filename);
        if (historyIndex != -1) {
          double reduction =
              0.95 * (1.0 - (historyIndex / config.historyLimit));
          weight *= (1.0 - max(0.0, reduction));
        }
      }
    }
    // --- Personality: CONSISTENT ---
    else if (config.personality == ShufflePersonality.consistent) {
      // 1. Favorites: Strong boost
      if (_favorites.contains(song.filename)) weight *= 3.0;

      // 2. Most played boost
      if (count > 10) weight *= 1.5;
      if (count > 50) weight *= 2.0;

      // 3. Anti-repeat: Relaxed
      if (_shuffleState.history.isNotEmpty) {
        int historyIndex = _shuffleState.history
            .indexWhere((e) => e.filename == song.filename);
        if (historyIndex != -1) {
          if (historyIndex < 10) {
            weight *= 0.05; // Don't play immediate repeats
          }
        }
      }
    }

    return max(0.0001, weight);
  }

  void _applyLinear(int currentIndex) {
    // ... (Existing Logic) ...
    if (_effectiveQueue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) {
      currentIndex = 0;
    }
    final currentItem = _effectiveQueue[currentIndex];
    final priorityItems = _effectiveQueue
        .where((item) => item.isPriority && item != currentItem)
        .toList();
    final originalItems = _originalQueue
        .where((item) => !priorityItems.any((p) => p.queueId == item.queueId))
        .toList();
    int originalIdx = originalItems
        .indexWhere((item) => item.song.filename == currentItem.song.filename);
    if (originalIdx != -1) {
      _effectiveQueue = [
        ...originalItems.sublist(0, originalIdx),
        currentItem,
        ...priorityItems,
        ...originalItems.sublist(originalIdx + 1)
      ];
    } else {
      _effectiveQueue = [currentItem, ...priorityItems, ...originalItems];
    }
    int newIndex = _effectiveQueue.indexOf(currentItem);
    _rebuildQueue(initialIndex: newIndex, startPlaying: _player.playing);
  }

  Future<void> _rebuildQueue(
      {int? initialIndex,
      bool startPlaying = true,
      Duration? initialPosition}) async {
    if (_effectiveQueue.isEmpty) return;

    final targetIndex = initialIndex ?? _player.currentIndex ?? 0;
    final currentItem = (targetIndex < _effectiveQueue.length)
        ? _effectiveQueue[targetIndex]
        : null;

    // Capture current player state reliably before rebuilding
    final sequenceState = _player.sequenceState;
    final currentMediaItem = sequenceState.currentSource?.tag as MediaItem?;
    final currentPosition = _player.position;

    Duration position = Duration.zero;
    if (initialPosition != null) {
      position = initialPosition;
    } else if (currentMediaItem != null && currentItem != null) {
      // If the song currently in the player is the same as the one we are pointing to in the new queue,
      // maintain the position.
      if (currentMediaItem.id == currentItem.song.filename) {
        position = currentPosition;
      }
    }

    final sources = await Future.wait(
        _effectiveQueue.map((item) => _createAudioSource(item)));
    await _player.setAudioSources(sources,
        initialIndex: targetIndex, initialPosition: position);

    if (startPlaying) await _player.play();
    _updateQueueNotifier();
  }

  Future<void> playNext(Song song) async {
    final currentIndex = _player.currentIndex ?? -1;
    final item = QueueItem(song: song, isPriority: true);
    _effectiveQueue.insert(currentIndex + 1, item);
    final source = await _createAudioSource(item);
    await _player.insertAudioSource(currentIndex + 1, source);
    _updateQueueNotifier();
    _savePlaybackState();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _effectiveQueue.removeAt(oldIndex);
    _effectiveQueue.insert(newIndex, item);
    await _player.moveAudioSource(oldIndex, newIndex);
    _updateQueueNotifier();
    _savePlaybackState();
  }

  Future<void> removeFromQueue(int index) async {
    _effectiveQueue.removeAt(index);
    await _player.removeAudioSourceAt(index);
    _updateQueueNotifier();
    _savePlaybackState();
  }

  void dispose() {
    _player.dispose();
    shuffleNotifier.dispose();
    _syncTimer?.cancel();
  }
}

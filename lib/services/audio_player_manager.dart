import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async'; // For Timer
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/shuffle_config.dart';
import 'stats_service.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'volume_monitor_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final StatsService _statsService;
  final StorageService _storageService;
  final String? _username;
  final Ref? _ref;

  List<QueueItem> _originalQueue = [];
  List<QueueItem> _effectiveQueue = [];
  List<Song> _allSongs = [];
  Map<String, Song> _songMap = {};

  // Flag to restrict auto-generation to original queue (e.g. for folder shuffle)
  bool _isRestrictedToOriginal = false;

  // Sync State
  Timer? _syncTimer;

  // User data for weighting (Fallback / Offline)
  List<String> _favorites = [];
  List<String> _suggestLess = [];
  List<String> _hidden = [];

  // Shuffle state
  ShuffleState _shuffleState = const ShuffleState();

  // Stats tracking state
  String? _currentSongFilename;
  DateTime? _playStartTime;
  bool _isCompleting = false;

  // Volume monitoring
  VolumeMonitorService? _volumeMonitorService;

  // New stats counters
  double _foregroundDuration = 0.0;
  double _backgroundDuration = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
  final ValueNotifier<ShuffleState> shuffleStateNotifier =
      ValueNotifier(const ShuffleState());
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier(null);

  AudioPlayerManager(this._statsService, this._storageService, this._username,
      [this._ref]) {
    WidgetsBinding.instance.addObserver(this);
    if (_username != null) {
      DatabaseService.instance.initForUser(_username!);
    }
    _initStatsListeners();
    _initPersistence();
    _initVolumeMonitoring();
  }

  AudioPlayer get player => _player;

  bool _isFavorite(String filename) {
    if (_favorites.contains(filename)) return true;
    final searchBasename = p.basename(filename);
    for (final fav in _favorites) {
      if (p.basename(fav) == searchBasename) return true;
    }
    return false;
  }

  bool _isSuggestLess(String filename) {
    if (_suggestLess.contains(filename)) return true;
    final searchBasename = p.basename(filename);
    for (final sl in _suggestLess) {
      if (p.basename(sl) == searchBasename) return true;
    }
    return false;
  }

  bool _isHidden(String filename) {
    if (_hidden.contains(filename)) return true;
    final searchBasename = p.basename(filename);
    for (final h in _hidden) {
      if (p.basename(h) == searchBasename) return true;
    }
    return false;
  }

  void setUserData(
      {List<String>? favorites,
      List<String>? suggestLess,
      List<String>? hidden}) {
    if (favorites != null) _favorites = favorites;
    if (suggestLess != null) _suggestLess = suggestLess;
    if (hidden != null) _hidden = hidden;
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
      _isRestrictedToOriginal = true;
    } else {
      if (_originalQueue.isEmpty) {
        _originalQueue = [QueueItem(song: song)];
        _isRestrictedToOriginal = false;
      }
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
        // Commit a progress slice when playback is paused to ensure data persistence.
        _flushStats(eventType: 'listen');
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
          currentSongNotifier.value = _songMap[newFilename];
          _savePlaybackState();
        }
      }
    });
  }

  void _generateOfflineNext() async {
    // Pick a random song from _allSongs using local weights
    if (_allSongs.isEmpty) return;

    List<Song> sourcePool = _isRestrictedToOriginal
        ? _originalQueue.map((q) => q.song).toList()
        : _allSongs;

    if (sourcePool.isEmpty) return;

    var candidates = sourcePool
        .where((s) => !_effectiveQueue.reversed
            .take(10)
            .any((q) => q.song.filename == s.filename))
        .toList();

    if (candidates.isEmpty) candidates = List.from(sourcePool);

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
    // syncShuffleState() removed - strictly local now

    // Start periodic sync removed - handled by SongsNotifier.refresh()
    // triggered on startup, resumes, and play events.
  }

  void _initVolumeMonitoring() {
    if (_ref != null) {
      _volumeMonitorService = VolumeMonitorService(
        onVolumeZero: () {
          // Read current settings each time to get up-to-date values
          final currentSettings = _ref!.read(settingsProvider);
          if (currentSettings.autoPauseOnVolumeZero && _player.playing) {
            _player.pause();
          }
        },
        onVolumeRestored: () {
          // Read current settings each time to get up-to-date values
          final currentSettings = _ref!.read(settingsProvider);
          // Auto-resume when volume is restored, but only if both settings are enabled
          // and the volume monitor service detected it was auto-paused
          if (currentSettings.autoPauseOnVolumeZero &&
              currentSettings.autoResumeOnVolumeRestore) {
            _player.play();
          }
        },
      );
      _volumeMonitorService?.initialize();

      // Listen to settings changes to update volume monitor enabled state
      _ref!.listen(settingsProvider, (previous, next) {
        if (previous?.autoPauseOnVolumeZero != next.autoPauseOnVolumeZero) {
          _volumeMonitorService
              ?.setAutoPauseEnabled(next.autoPauseOnVolumeZero);
        }
      });

      // Set initial enabled state
      final initialSettings = _ref!.read(settingsProvider);
      _volumeMonitorService
          ?.setAutoPauseEnabled(initialSettings.autoPauseOnVolumeZero);
    }
  }

  Future<ShuffleState?> syncShuffleState() async {
    // Strictly local now, but keep as no-op to avoid breaking other calls
    return _shuffleState;
  }

  Future<void> _saveShuffleState() async {
    if (_username == null) return;
    await _storageService.saveShuffleState(_username!, _shuffleState.toJson());
    // _statsService.updateShuffleState removed - strictly local
  }

  Future<void> _savePlaybackState() async {
    if (_username == null) return;

    final currentIndex = _player.currentIndex;
    final currentSong =
        (currentIndex != null && currentIndex < _effectiveQueue.length)
            ? _effectiveQueue[currentIndex].song
            : null;

    final state = {
      'last_song_filename': currentSong?.filename,
      'last_effective_queue': _effectiveQueue.map((e) => e.toJson()).toList(),
      'last_original_queue': _originalQueue.map((e) => e.toJson()).toList(),
      'last_position_ms': _player.position.inMilliseconds,
      'is_restricted_to_original': _isRestrictedToOriginal,
    };

    await _storageService.savePlaybackState(_username!, state);
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
    final totalLength =
        (song?.duration?.inMilliseconds.toDouble() ?? 0.0) / 1000.0;

    double finalDuration = _foregroundDuration + _backgroundDuration;
    if (finalDuration > 0.5) {
      _statsService.trackStats({
        'username': _username!,
        'song_filename': _currentSongFilename!,
        'duration_played': finalDuration,
        'event_type': eventType,
        'foreground_duration': _foregroundDuration,
        'background_duration': _backgroundDuration,
        'total_length': totalLength,
      });

      // Add to local history if completed OR played for at least 5 seconds (to treat as a "seen" song for anti-repeat)
      if (eventType == 'complete' || finalDuration > 5.0) {
        _addToShuffleHistory(_currentSongFilename!);
      }
    }
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
      _playStartTime = null;

      // Trigger background sync on play events as requested
      if (_ref != null) {
        Future.delayed(const Duration(seconds: 1), () {
          _ref!.read(songsProvider.notifier).refresh(isBackground: true);
        });
      }
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

    // 1. Process session finalization events before the app is suspended.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushStats(eventType: 'listen');
      _savePlaybackState();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Ensure that the final 'listen' event is committed to the database
      // before the process is terminated or suspended.
      _statsService.flush();
    }

    // 2. Adjust stats tracking mode based on lifecycle state.
    // Background mode enables batching to reduce CPU wake-ups.
    final isBackground = state != AppLifecycleState.resumed;
    _statsService.setBackground(isBackground);

    _appLifecycleState = state;
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    _allSongs = songs;
    _songMap = {for (var s in songs) s.filename: s};
    _isRestrictedToOriginal = false;
    await _player.setShuffleModeEnabled(false);

    if (_username != null) {
      await DatabaseService.instance.initForUser(_username!);
    }

    // 1. Fallback to Local Storage (Always local-first now)
    final savedState = _username != null
        ? await _storageService.loadPlaybackState(_username!)
        : null;

    if (savedState != null) {
      try {
        final List<dynamic> effJson = savedState['last_effective_queue'] ?? [];
        final List<dynamic> origJson = savedState['last_original_queue'] ?? [];

        // Parse effective queue and filter out items with missing files
        _effectiveQueue = effJson.expand((j) {
          try {
            final queueItem = QueueItem.fromJson(j);
            // Check if the song file still exists
            if (queueItem.song.url.isNotEmpty) {
              final file = File(queueItem.song.url);
              if (file.existsSync()) {
                return [queueItem];
              } else {
                debugPrint(
                    'Skipping queue item with missing file: ${queueItem.song.url}');
                return <QueueItem>[];
              }
            } else {
              debugPrint(
                  'Skipping queue item with empty URL: ${queueItem.song.filename}');
              return <QueueItem>[];
            }
          } catch (e) {
            debugPrint('Failed to parse a QueueItem from effectiveQueue: $e');
            return <QueueItem>[];
          }
        }).toList();

        // Parse original queue and filter out items with missing files
        _originalQueue = origJson.expand((j) {
          try {
            final queueItem = QueueItem.fromJson(j);
            // Check if the song file still exists
            if (queueItem.song.url.isNotEmpty) {
              final file = File(queueItem.song.url);
              if (file.existsSync()) {
                return [queueItem];
              } else {
                debugPrint(
                    'Skipping queue item with missing file: ${queueItem.song.url}');
                return <QueueItem>[];
              }
            } else {
              debugPrint(
                  'Skipping queue item with empty URL: ${queueItem.song.filename}');
              return <QueueItem>[];
            }
          } catch (e) {
            debugPrint('Failed to parse a QueueItem from originalQueue: $e');
            return <QueueItem>[];
          }
        }).toList();

        // If both queues are empty after filtering, fall back to a fresh state
        if (_effectiveQueue.isEmpty && _originalQueue.isEmpty) {
          debugPrint(
              'Both queues are empty after filtering for missing files, starting fresh');
        } else {
          _isRestrictedToOriginal =
              savedState['is_restricted_to_original'] ?? false;

          final savedPositionMs = savedState['last_position_ms'] ?? 0;
          final lastSongFilename = savedState['last_song_filename'];

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
        }
      } catch (e) {
        // Ignore malformed persistence state, fallback to default
      }
    } else {
      // Compatibility fallback to SharedPreferences for older versions
      final prefs = await SharedPreferences.getInstance();
      final savedEffectiveQueueJson = prefs.getString('last_effective_queue');
      final savedOriginalQueueJson = prefs.getString('last_original_queue');
      final savedPositionMs = prefs.getInt('last_position_ms') ?? 0;
      final lastSongFilename = prefs.getString('last_song_filename');

      if (savedEffectiveQueueJson != null && savedOriginalQueueJson != null) {
        try {
          final List<dynamic> effJson = jsonDecode(savedEffectiveQueueJson);
          final List<dynamic> origJson = jsonDecode(savedOriginalQueueJson);

          // Parse effective queue and filter out items with missing files
          _effectiveQueue = effJson.expand((j) {
            try {
              final queueItem = QueueItem.fromJson(j);
              // Check if the song file still exists
              if (queueItem.song.url.isNotEmpty) {
                final file = File(queueItem.song.url);
                if (file.existsSync()) {
                  return [queueItem];
                } else {
                  debugPrint(
                      'Skipping legacy queue item with missing file: ${queueItem.song.url}');
                  return <QueueItem>[];
                }
              } else {
                debugPrint(
                    'Skipping legacy queue item with empty URL: ${queueItem.song.filename}');
                return <QueueItem>[];
              }
            } catch (e) {
              debugPrint(
                  'Failed to parse a QueueItem from legacy effectiveQueue: $e');
              return <QueueItem>[];
            }
          }).toList();

          // Parse original queue and filter out items with missing files
          _originalQueue = origJson.expand((j) {
            try {
              final queueItem = QueueItem.fromJson(j);
              // Check if the song file still exists
              if (queueItem.song.url.isNotEmpty) {
                final file = File(queueItem.song.url);
                if (file.existsSync()) {
                  return [queueItem];
                } else {
                  debugPrint(
                      'Skipping legacy queue item with missing file: ${queueItem.song.url}');
                  return <QueueItem>[];
                }
              } else {
                debugPrint(
                    'Skipping legacy queue item with empty URL: ${queueItem.song.filename}');
                return <QueueItem>[];
              }
            } catch (e) {
              debugPrint(
                  'Failed to parse a QueueItem from legacy originalQueue: $e');
              return <QueueItem>[];
            }
          }).toList();

          // If both queues are empty after filtering, fall back to a fresh state
          if (_effectiveQueue.isEmpty && _originalQueue.isEmpty) {
            debugPrint(
                'Both legacy queues are empty after filtering for missing files, starting fresh');
          } else {
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
            currentSongNotifier.value = _effectiveQueue[initialIndex].song;
            return;
          }
        } catch (e) {
          // Ignore
        }
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

  void refreshSongs(List<Song> newSongs) {
    _allSongs = newSongs.where((s) => !_isHidden(s.filename)).toList();
    _songMap = {for (var s in _allSongs) s.filename: s};

    // Check if current song was renamed (filename changed) or moved
    final currentIdx = _player.currentIndex;
    final currentItemBefore =
        (currentIdx != null && currentIdx < _effectiveQueue.length)
            ? _effectiveQueue[currentIdx]
            : null;

    // Update URLs and filenames in queues to reflect moves/renames
    _effectiveQueue = _effectiveQueue.map((item) {
      final updatedSong = _songMap[item.song.filename];
      return updatedSong != null ? item.copyWith(song: updatedSong) : item;
    }).toList();

    _originalQueue = _originalQueue.map((item) {
      final updatedSong = _songMap[item.song.filename];
      return updatedSong != null ? item.copyWith(song: updatedSong) : item;
    }).toList();

    _updateQueueNotifier();
    _savePlaybackState();

    // If something changed in the current item, we need to rebuild the player queue
    // to update the AudioSource (which contains the filename/URL)
    if (currentIdx != null && currentItemBefore != null) {
      final currentItemAfter = _effectiveQueue[currentIdx];
      if (currentItemBefore.song.url != currentItemAfter.song.url ||
          currentItemBefore.song.filename != currentItemAfter.song.filename) {
        _rebuildQueue(initialIndex: currentIdx, startPlaying: _player.playing);
      }
    }
  }

  Future<AudioSource> _createAudioSource(QueueItem item) async {
    final song = item.song;

    final Uri audioUri = Uri.file(song.url);

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

  Future<void> shuffleAndPlay(List<Song> songs,
      {bool isRestricted = false}) async {
    if (songs.isEmpty) return;

    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: true),
    );
    shuffleNotifier.value = true;
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();

    // Pick random start
    final randomIdx = Random().nextInt(songs.length);

    if (isRestricted) {
      await playSong(songs[randomIdx], contextQueue: songs, startPlaying: true);
    } else {
      // For non-restricted, we update the original queue but don't lock it
      _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      _isRestrictedToOriginal = false;
      await playSong(songs[randomIdx], startPlaying: true);
    }
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
    final shuffledNormal =
        await _weightedShuffle(normalItems, lastItem: currentItem);

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

    // Fetch local play counts and skip stats for weighting
    final playCounts = await DatabaseService.instance.getPlayCounts();
    final skipStats = await DatabaseService.instance.getSkipStats();

    final result = <QueueItem>[];
    final remaining = List<QueueItem>.from(items);
    QueueItem? prev = lastItem;

    // Calculate max play count for adaptive consistent mode
    int maxPlayCount = 0;
    if (playCounts.isNotEmpty) {
      maxPlayCount = playCounts.values.fold(0, max);
    }

    while (remaining.isNotEmpty) {
      final weights = remaining
          .map((item) =>
              _calculateWeight(item, prev, playCounts, skipStats, maxPlayCount))
          .toList();
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

  double _calculateWeight(
      QueueItem item,
      QueueItem? prev,
      Map<String, int> playCounts,
      Map<String, ({int count, double avgRatio})> skipStats,
      int maxPlayCount) {
    double weight = 1.0;
    final song = item.song;
    final config = _shuffleState.config;
    final count = playCounts[song.filename] ?? 0;

    // 1. User Preferences
    if (_isFavorite(song.filename)) {
      if (config.personality == ShufflePersonality.consistent) {
        weight *= 1.4; // +40% for consistent
      } else if (config.personality == ShufflePersonality.explorer) {
        weight *= 1.12; // +12% for explorer
      } else {
        weight *= config.favoriteMultiplier; // +20% default (1.2)
      }
    }
    if (_isSuggestLess(song.filename)) {
      weight *= 0.2; // 80% penalty globally
    }

    // 2. Personality Weights
    if (config.personality == ShufflePersonality.explorer) {
      if (count == 0) {
        weight *= 1.2; // 20% reward for never played
      }
    } else if (config.personality == ShufflePersonality.consistent) {
      // Adaptive Threshold for new users
      int threshold = 10;
      if (maxPlayCount < 10) {
        threshold = max(1, (maxPlayCount * 0.7).floor());
      } else if (maxPlayCount < 20) {
        threshold = 5;
      }

      if (count >= threshold && count > 0) {
        weight *= 1.3; // 30% reward for often played
      }
    } else if (config.personality == ShufflePersonality.defaultMode) {
      // Default uses streak breaker
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

    // 3. Global Recency Penalty (Last 100 events)
    if (_shuffleState.history.isNotEmpty) {
      int historyIndex =
          _shuffleState.history.indexWhere((e) => e.filename == song.filename);
      if (historyIndex != -1 && historyIndex < 100) {
        int n = historyIndex + 1;
        // n=1 (most recent) -> 100% penalty
        // n=2 -> 98% penalty
        // n=99 -> 1% penalty
        int penaltyPercent = (n == 1) ? 100 : (100 - n);
        if (penaltyPercent > 0) {
          weight *= (1.0 - (penaltyPercent / 100.0));
        }
      }
    }

    // 4. Global Skip Penalty
    final stats = skipStats[song.filename];
    if (stats != null && stats.count >= 3 && stats.avgRatio <= 0.15) {
      weight *= 0.05; // 95% penalty
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

  void forceFlushCurrentStats() {
    _flushStats(eventType: 'listen');
    _statsService.flush();
  }

  void dispose() {
    _volumeMonitorService?.dispose();
    _player.dispose();
    shuffleNotifier.dispose();
    _syncTimer?.cancel();
  }
}

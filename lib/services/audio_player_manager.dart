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
import 'color_extraction_service.dart';
import '../providers/theme_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class AudioPlayerManager extends WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final StatsService _statsService;
  final StorageService _storageService;
  final Ref? _ref;

  List<QueueItem> _originalQueue = [];
  List<QueueItem> _effectiveQueue = [];
  List<Song> _allSongs = [];
  Map<String, Song> _songMap = {};

  // Flag to restrict auto-generation to original queue (e.g. for folder shuffle)
  bool _isRestrictedToOriginal = false;

  // User data for weighting (Fallback / Offline)
  List<String> _favorites = [];
  List<String> _suggestLess = [];
  List<String> _hidden = [];

  // Merged song groups for shuffle weighting
  Map<String, List<String>> _mergedGroups = {};

  // Shuffle state
  ShuffleState _shuffleState = const ShuffleState();

  // Stats tracking state
  String? _currentSongFilename;
  String? _currentPlaylistId;
  DateTime? _playStartTime;
  bool _isCompleting = false;

  // Previous session tracking for ignoring quick skips of resumed songs
  String? _previousSessionSongFilename;
  bool _isResumedFromPreviousSession = false;

  // Volume monitoring
  VolumeMonitorService? _volumeMonitorService;

  // Fading and delay state
  bool _isFadingIn = false;
  bool _isFadingOut = false;
  bool _isWaitingForDelay = false;
  String? _lastFadedFilename;
  Timer? _fadeTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<SequenceState?>? _sequenceSubscription;

  // New stats counters
  double _foregroundDuration = 0.0;
  double _backgroundDuration = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
  final ValueNotifier<ShuffleState> shuffleStateNotifier =
      ValueNotifier(const ShuffleState());
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier(null);

  AudioPlayerManager(this._statsService, this._storageService, [this._ref]) {
    WidgetsBinding.instance.addObserver(this);
    // DatabaseService is global now, initialized in main or providers
    _initStatsListeners();
    _initPersistence();
    _initVolumeMonitoring();
    _initFadingListeners();
  }

  AudioPlayer get player => _player;
  String? get currentPlaylistId => _currentPlaylistId;

  Future<bool> stopIfCurrentSong(String fileUrl) async {
    final current = currentSongNotifier.value;
    if (current == null) return false;
    if (!p.equals(current.url, fileUrl)) return false;
    try {
      await _player.stop();
      return true;
    } catch (e) {
      debugPrint('AudioPlayerManager: failed to stop for edit: $e');
      return false;
    }
  }

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
      List<String>? hidden,
      Map<String, List<String>>? mergedGroups}) {
    if (favorites != null) _favorites = favorites;
    if (suggestLess != null) _suggestLess = suggestLess;
    if (hidden != null) _hidden = hidden;
    if (mergedGroups != null) _mergedGroups = mergedGroups;
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
      {List<Song>? contextQueue,
      String? playlistId,
      bool startPlaying = true,
      bool forceLinear = false}) async {
    _resetFading();
    await _player.setShuffleModeEnabled(false);
    _currentPlaylistId = playlistId;

    // Automatically disable shuffle if forceLinear is requested
    if (forceLinear && _shuffleState.config.enabled) {
      _shuffleState = _shuffleState.copyWith(
        config: _shuffleState.config.copyWith(enabled: false),
      );
      shuffleStateNotifier.value = _shuffleState;
      shuffleNotifier.value = false;
      await _saveShuffleState();
    }

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

    if (_shuffleState.config.enabled && !forceLinear) {
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
          if (!_isCompleting) {
            // Check if this is a quick skip of a resumed song from previous session
            final shouldIgnore = _isResumedFromPreviousSession &&
                _currentSongFilename == _previousSessionSongFilename &&
                _foregroundDuration + _backgroundDuration <= 10.0;

            if (!shouldIgnore) {
              _flushStats(eventType: 'skip');
            }
          }
        }
        if (_currentSongFilename != newFilename) {
          _isCompleting = false;
          _currentSongFilename = newFilename;
          _foregroundDuration = 0.0;
          _backgroundDuration = 0.0;
          _playStartTime = _player.playing ? DateTime.now() : null;
          final song = _songMap[newFilename];
          currentSongNotifier.value = song;
          _isResumedFromPreviousSession = false;
          _savePlaybackState();

          // Extract color from cover
          if (song != null && _ref != null) {
            ColorExtractionService.extractColor(song.coverUrl).then((color) {
              _ref!.read(themeProvider.notifier).updateExtractedColor(color);
            });
          }
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
    final localStateData = await _storageService.loadShuffleState();
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

  void _initFadingListeners() {
    _positionSubscription = _player.positionStream.listen((position) {
      if (_ref == null) return;
      final settings = _ref!.read(settingsProvider);
      final fadeOutDuration = settings.fadeOutDuration;
      final delayDuration = settings.delayDuration;

      final totalDuration = _player.duration;
      if (totalDuration == null) return;

      final remaining = totalDuration - position;

      // 1. Delay logic (pause at 1s remaining)
      if (delayDuration > 0 &&
          remaining.inMilliseconds <= 1000 &&
          remaining.inMilliseconds > 0 &&
          !_isWaitingForDelay &&
          _player.playing) {
        _isWaitingForDelay = true;
        _player.pause();

        // Subtract 1 second from the setting because we are pausing 1s early
        final adjustedDelayMs = max(0.0, (delayDuration - 1.0) * 1000).toInt();

        Future.delayed(Duration(milliseconds: adjustedDelayMs), () {
          // Verify we're still on the same song before resuming
          if (_player.duration == totalDuration) {
            _player.play();
          }
        });
      }

      // 2. Fade Out logic
      if (fadeOutDuration > 0) {
        if (remaining.inMilliseconds <= fadeOutDuration * 1000 &&
            remaining.inMilliseconds > 0 &&
            _player.playing) {
          _isFadingOut = true;
          final volume = (remaining.inMilliseconds / (fadeOutDuration * 1000))
              .clamp(0.0, 1.0);
          _player.setVolume(volume);
        } else if (_isFadingOut &&
            remaining.inMilliseconds > fadeOutDuration * 1000) {
          _isFadingOut = false;
          if (!_isFadingIn) {
            _player.setVolume(1.0);
          }
        }
      } else {
        if (!_isFadingIn && _player.volume != 1.0) {
          _player.setVolume(1.0);
        }
      }
    });

    _sequenceSubscription = _player.sequenceStateStream.listen((state) async {
      if (_ref == null) return;
      final settings = _ref!.read(settingsProvider);

      final currentItem = state.currentSource?.tag;
      if (currentItem is MediaItem) {
        final newFilename = currentItem.id;
        if (_lastFadedFilename != newFilename) {
          _lastFadedFilename = newFilename;
          _isWaitingForDelay = false;
          _isFadingOut = false;

          if (settings.fadeInDuration > 0) {
            _startFadeIn(settings.fadeInDuration);
          } else {
            _player.setVolume(1.0);
          }
        }
      }
    });
  }

  void _startFadeIn(double duration) {
    _fadeTimer?.cancel();
    _isFadingIn = true;
    _player.setVolume(0.0);

    final startTime = DateTime.now();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final targetMs = duration * 1000;

      if (elapsed >= targetMs) {
        _player.setVolume(1.0);
        _isFadingIn = false;
        timer.cancel();
      } else {
        _player.setVolume(elapsed / targetMs);
      }
    });
  }

  void _resetFading() {
    _fadeTimer?.cancel();
    _isFadingIn = false;
    _isFadingOut = false;
    _isWaitingForDelay = false;
    _player.setVolume(1.0);
  }

  Future<ShuffleState?> syncShuffleState() async {
    // Strictly local now, but keep as no-op to avoid breaking other calls
    return _shuffleState;
  }

  Future<void> _saveShuffleState() async {
    await _storageService.saveShuffleState(_shuffleState.toJson());
    // _statsService.updateShuffleState removed - strictly local
  }

  Future<void> _savePlaybackState() async {
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
      'current_playlist_id': _currentPlaylistId,
    };

    await _storageService.savePlaybackState(state);
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
    if (_currentSongFilename == null) return;
    if (_playStartTime != null) _updateDurations();

    final song = _songMap[_currentSongFilename!];
    final totalLength =
        (song?.duration?.inMilliseconds.toDouble() ?? 0.0) / 1000.0;

    double finalDuration = _foregroundDuration + _backgroundDuration;

    // Categorization logic
    String finalEventType = eventType;

    // 1. Completion exceptions: if skipped/stopped in last 10s or over 1.0 ratio, it's a complete
    if (totalLength > 0) {
      final double ratio = finalDuration / totalLength;
      final double remaining = totalLength - finalDuration;

      if (remaining <= 10.0 || ratio >= 1.0) {
        finalEventType = 'complete';
      } else if (ratio < 0.10) {
        // If played for less than 10% of duration, count as skip
        finalEventType = 'skip';
      } else if (eventType == 'listen') {
        // If it was a 'listen' event (pause/lifecycle change) but it's NOT the last song
        // (meaning another song will be played in this session),
        // it's actually a 'skip' if it's not the last thing recorded.
        // However, at the time of _flushStats(listen), we don't always know if another song will follow.
        // But per requirements: "when theres a song after it it should count a 'listen' as a skip"
        // This is handled by 'skip' being passed when song actually switches.
      }
    }

    if (finalDuration > 0.5) {
      _statsService.trackStats({
        'song_filename': _currentSongFilename!,
        'duration_played': finalDuration,
        'event_type': finalEventType,
        'foreground_duration': _foregroundDuration,
        'background_duration': _backgroundDuration,
        'total_length': totalLength,
      });

      // Add to local history if completed OR played for at least 5 seconds
      if (finalEventType == 'complete' || finalDuration > 5.0) {
        _addToShuffleHistory(_currentSongFilename!);
      }
    }
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
      _playStartTime = null;

      // Ensure stats are committed to DB immediately on song end/skip
      // This prevents data loss without needing an expensive full library scan.
      _statsService.flush();
    } else {
      if (_playStartTime != null) _playStartTime = DateTime.now();
    }
  }

  void _addToShuffleHistory(String filename) {
    // History is now tracked automatically via play events in the database
    // No need to manually maintain a separate history list
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

    await DatabaseService.instance.init();

    // 1. Fallback to Local Storage (Always local-first now)
    final savedState = await _storageService.loadPlaybackState();

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
          _currentPlaylistId = savedState['current_playlist_id'];

          final savedPositionMs = savedState['last_position_ms'] ?? 0;
          final lastSongFilename = savedState['last_song_filename'];

          int initialIndex = 0;
          Duration? resumePosition;

          if (lastSongFilename != null) {
            initialIndex = _effectiveQueue
                .indexWhere((item) => item.song.filename == lastSongFilename);
            if (initialIndex != -1) {
              resumePosition = Duration(milliseconds: savedPositionMs);
              _previousSessionSongFilename = lastSongFilename;
              _isResumedFromPreviousSession = true;
            } else {
              initialIndex = 0;
            }
          }

          await _rebuildQueue(
              initialIndex: initialIndex,
              startPlaying: false,
              initialPosition: resumePosition);

          // Extract color for initial song
          if (_ref != null) {
            final initialSong = _effectiveQueue[initialIndex].song;
            ColorExtractionService.extractColor(initialSong.coverUrl)
                .then((color) {
              _ref!.read(themeProvider.notifier).updateExtractedColor(color);
            });
          }
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
                _previousSessionSongFilename = lastSongFilename;
                _isResumedFromPreviousSession = true;
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
    // to update the AudioSource (which contains the filename/URL and artUri)
    if (currentIdx != null && currentItemBefore != null) {
      final currentItemAfter = _effectiveQueue[currentIdx];
      if (currentItemBefore.song.url != currentItemAfter.song.url ||
          currentItemBefore.song.filename != currentItemAfter.song.filename ||
          currentItemBefore.song.coverUrl != currentItemAfter.song.coverUrl) {
        _rebuildQueue(initialIndex: currentIdx, startPlaying: _player.playing);
      }
    }
  }

  Future<void> refreshQueue() async {
    if (_effectiveQueue.isEmpty) return;

    final currentIndex = _player.currentIndex ?? -1;
    if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) return;

    if (_shuffleState.config.enabled) {
      final currentItem = _effectiveQueue[currentIndex];
      final prefix = _effectiveQueue.sublist(0, currentIndex + 1);
      final priorityItems = _effectiveQueue
          .skip(currentIndex + 1)
          .where((item) => item.isPriority)
          .toList();

      final sourcePool = _isRestrictedToOriginal
          ? _originalQueue.map((q) => q.song).toList()
          : _allSongs;

      if (sourcePool.isEmpty) return;

      final excluded = <String>{
        ...prefix.map((item) => item.song.filename),
        ...priorityItems.map((item) => item.song.filename),
      };

      final candidates = sourcePool
          .where((song) => !excluded.contains(song.filename))
          .toList();
      final candidateItems = candidates.map((s) => QueueItem(song: s)).toList();

      final shuffled =
          await _weightedShuffle(candidateItems, lastItem: currentItem);

      _effectiveQueue = [...prefix, ...priorityItems, ...shuffled];
      await _rebuildQueue(
          initialIndex: currentIndex, startPlaying: _player.playing);
      return;
    }

    _applyLinear(currentIndex);
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
          'hasLyrics':
              song.hasLyrics, // Use the actual flag from the song model
          'remoteUrl': song.url,
          'queueId': item.queueId,
          'isPriority': item.isPriority,
          'androidStopForegroundOnPause': true,
          'audioPath': song.url,
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

  /// Replaces the current queue with a new set of songs.
  /// If [forceLinear] is true, it replaces everything and starts from the first song.
  Future<void> replaceQueue(List<Song> songs,
      {String? playlistId, bool forceLinear = false}) async {
    if (songs.isEmpty) return;
    _currentPlaylistId = playlistId;

    final currentSong = currentSongNotifier.value;
    final isPlaying = _player.playing;

    if (forceLinear) {
      _resetFading();
      await _player.setShuffleModeEnabled(false);

      // Automatically disable shuffle if forceLinear is requested
      if (_shuffleState.config.enabled) {
        _shuffleState = _shuffleState.copyWith(
          config: _shuffleState.config.copyWith(enabled: false),
        );
        shuffleStateNotifier.value = _shuffleState;
        shuffleNotifier.value = false;
        await _saveShuffleState();
      }

      _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      _isRestrictedToOriginal = true;
      _effectiveQueue = List.from(_originalQueue);
      await _rebuildQueue(initialIndex: 0, startPlaying: true);
      _savePlaybackState();
      _updateQueueNotifier();
      return;
    }

    // Filter out the currently playing song if it's first in the list
    List<Song> queueSongs = List.from(songs);
    if (currentSong != null &&
        isPlaying &&
        queueSongs.isNotEmpty &&
        queueSongs.first.filename == currentSong.filename) {
      queueSongs.removeAt(0);
    }

    if (queueSongs.isEmpty) return;

    _resetFading();
    await _player.setShuffleModeEnabled(false);

    // Set up the new queue
    _originalQueue = queueSongs.map((s) => QueueItem(song: s)).toList();
    _isRestrictedToOriginal = true;

    if (_shuffleState.config.enabled && !forceLinear) {
      // If shuffle is enabled, we need to shuffle the remaining songs
      final shuffledItems = await _weightedShuffle(
        _originalQueue.map((item) => QueueItem(song: item.song)).toList(),
        lastItem: currentSong != null ? QueueItem(song: currentSong) : null,
      );

      // Keep current song at the front if playing
      if (currentSong != null && isPlaying) {
        final currentItem = QueueItem(song: currentSong);
        _effectiveQueue = [currentItem, ...shuffledItems];
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      } else {
        _effectiveQueue = shuffledItems;
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      }
    } else {
      // Linear queue
      if (currentSong != null && isPlaying) {
        // Add current song to front, then the new queue
        final currentItem = QueueItem(song: currentSong);
        _effectiveQueue = [currentItem, ..._originalQueue];
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      } else {
        _effectiveQueue = List.from(_originalQueue);
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      }
    }

    _savePlaybackState();
    _updateQueueNotifier();
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

    // Fetch local play counts, skip stats, and history for weighting
    final playCounts = await DatabaseService.instance.getPlayCounts();
    final skipStats = await DatabaseService.instance.getSkipStats();
    final playHistory = await DatabaseService.instance
        .getPlayHistory(limit: _shuffleState.config.historyLimit);

    // Group items by merge group - each merge group becomes one "virtual" item
    final Map<String, List<QueueItem>> mergeGroups = {};
    final List<QueueItem> standaloneItems = [];

    for (final item in items) {
      final groupId = _getMergedGroupId(item.song.filename);
      if (groupId != null) {
        mergeGroups.putIfAbsent(groupId, () => []).add(item);
      } else {
        standaloneItems.add(item);
      }
    }

    // Create virtual items for shuffle: standalone items + merge groups (as units)
    final virtualItems = <_VirtualShuffleItem>[];

    // Add standalone items
    for (final item in standaloneItems) {
      virtualItems.add(_VirtualShuffleItem(
        type: _VirtualItemType.standalone,
        items: [item],
        representative: item,
      ));
    }

    // Add merge groups as single virtual items
    for (final entry in mergeGroups.entries) {
      // Use the first item as representative for artist/album checks
      // The actual song will be chosen later based on favorites/suggest-less
      virtualItems.add(_VirtualShuffleItem(
        type: _VirtualItemType.mergeGroup,
        items: entry.value,
        representative: entry.value.first,
        groupId: entry.key,
      ));
    }

    // Calculate max play count for adaptive consistent mode
    int maxPlayCount = 0;
    if (playCounts.isNotEmpty) {
      maxPlayCount = playCounts.values.fold(0, max);
    }

    final result = <QueueItem>[];
    final remaining = List<_VirtualShuffleItem>.from(virtualItems);
    _VirtualShuffleItem? prev = lastItem != null
        ? _createVirtualItemFromQueueItem(lastItem, mergeGroups)
        : null;

    while (remaining.isNotEmpty) {
      final weights = remaining
          .map((item) => _calculateVirtualWeight(
              item, prev, playCounts, skipStats, maxPlayCount, playHistory))
          .toList();

      final totalWeight = weights.fold(0.0, (a, b) => a + b);
      if (totalWeight <= 0) {
        // Fallback: shuffle remaining and select randomly from each group
        remaining.shuffle();
        for (final virtualItem in remaining) {
          final selected = _selectSongFromVirtualItem(virtualItem);
          if (selected != null) {
            result.add(selected);
          }
        }
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

      final selectedVirtual = remaining[selectedIdx];
      final selectedSong = _selectSongFromVirtualItem(selectedVirtual);

      if (selectedSong != null) {
        result.add(selectedSong);
        prev = selectedVirtual;
      }

      remaining.removeAt(selectedIdx);
    }

    return result;
  }

  /// Creates a virtual item from a queue item for comparison purposes
  _VirtualShuffleItem? _createVirtualItemFromQueueItem(
      QueueItem item, Map<String, List<QueueItem>> mergeGroups) {
    final groupId = _getMergedGroupId(item.song.filename);
    if (groupId != null && mergeGroups.containsKey(groupId)) {
      return _VirtualShuffleItem(
        type: _VirtualItemType.mergeGroup,
        items: mergeGroups[groupId]!,
        representative: item,
        groupId: groupId,
      );
    }
    return _VirtualShuffleItem(
      type: _VirtualItemType.standalone,
      items: [item],
      representative: item,
    );
  }

  /// Gets the merge group ID for a filename, or null if not in a group
  String? _getMergedGroupId(String filename) {
    for (final entry in _mergedGroups.entries) {
      if (entry.value.contains(filename)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Selects an actual song from a virtual item based on favorites/suggest-less
  QueueItem? _selectSongFromVirtualItem(_VirtualShuffleItem virtualItem) {
    if (virtualItem.items.length == 1) {
      return virtualItem.items.first;
    }

    // For merge groups, select based on weighted random with favorites/suggest-less
    final weights = virtualItem.items.map((item) {
      double weight = 1.0;
      if (_isFavorite(item.song.filename)) {
        weight *= 2.0; // Favorites get 2x boost
      }
      if (_isSuggestLess(item.song.filename)) {
        weight *= 0.2; // Suggest-less get 80% penalty
      }
      return weight;
    }).toList();

    final totalWeight = weights.fold(0.0, (a, b) => a + b);
    if (totalWeight <= 0) {
      return virtualItem.items.first;
    }

    double randomValue = Random().nextDouble() * totalWeight;
    double cumulative = 0.0;
    for (int i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (randomValue <= cumulative) {
        return virtualItem.items[i];
      }
    }
    return virtualItem.items.last;
  }

  /// Calculates weight for a virtual item (merge group or standalone song)
  double _calculateVirtualWeight(
    _VirtualShuffleItem item,
    _VirtualShuffleItem? prev,
    Map<String, int> playCounts,
    Map<String, ({int count, double avgRatio})> skipStats,
    int maxPlayCount,
    List<
            ({
              String filename,
              double timestamp,
              double playRatio,
              String eventType
            })>
        playHistory,
  ) {
    double weight = 1.0;
    final representative = item.representative;
    final config = _shuffleState.config;

    // Get effective play count for the group (sum of all songs in group)
    int groupPlayCount = 0;
    if (item.type == _VirtualItemType.mergeGroup) {
      for (final queueItem in item.items) {
        groupPlayCount += playCounts[queueItem.song.filename] ?? 0;
      }
    } else {
      groupPlayCount = playCounts[representative.song.filename] ?? 0;
    }

    // HIERARCHY 1 (TOP PRIORITY): Global Recency Penalty
    final bool isConsistentMode =
        config.personality == ShufflePersonality.consistent;
    final bool isCustomMode = config.personality == ShufflePersonality.custom;
    final bool shouldAvoidRepeatingSongs =
        isCustomMode ? config.avoidRepeatingSongs : !isConsistentMode;

    if (shouldAvoidRepeatingSongs && playHistory.isNotEmpty) {
      int historyIndex = -1;
      double playRatioInHistory = 0.0;

      // Check if any song in the group is in history
      for (int i = 0; i < playHistory.length; i++) {
        if (item.type == _VirtualItemType.mergeGroup) {
          for (final queueItem in item.items) {
            if (playHistory[i].filename == queueItem.song.filename) {
              if (historyIndex == -1 || i < historyIndex) {
                historyIndex = i;
                playRatioInHistory = playHistory[i].playRatio;
              }
              break;
            }
          }
        } else {
          if (playHistory[i].filename == representative.song.filename) {
            historyIndex = i;
            playRatioInHistory = playHistory[i].playRatio;
            break;
          }
        }
      }

      if (historyIndex != -1 && historyIndex < 200) {
        double basePenaltyPercent;

        // Consistent mode: relaxed penalties (allows familiar songs)
        // Other modes: aggressive penalties (avoids recent songs)
        if (isConsistentMode) {
          // Relaxed penalties for Consistent mode
          if (historyIndex < 10) {
            basePenaltyPercent = 60.0;
          } else if (historyIndex < 20) {
            basePenaltyPercent = 50.0;
          } else if (historyIndex < 30) {
            basePenaltyPercent = 40.0;
          } else if (historyIndex < 40) {
            basePenaltyPercent = 30.0;
          } else if (historyIndex < 50) {
            basePenaltyPercent = 20.0;
          } else if (historyIndex < 60) {
            basePenaltyPercent = 15.0;
          } else if (historyIndex < 80) {
            basePenaltyPercent = 10.0;
          } else if (historyIndex < 100) {
            basePenaltyPercent = 5.0;
          } else {
            basePenaltyPercent = 0.0;
          }
        } else {
          // Aggressive penalties for Explorer/Default/Custom modes
          if (historyIndex < 10) {
            basePenaltyPercent = 99.9;
          } else if (historyIndex < 20) {
            basePenaltyPercent = 99.0;
          } else if (historyIndex < 30) {
            basePenaltyPercent = 97.0;
          } else if (historyIndex < 40) {
            basePenaltyPercent = 94.0;
          } else if (historyIndex < 50) {
            basePenaltyPercent = 90.0;
          } else if (historyIndex < 60) {
            basePenaltyPercent = 85.0;
          } else if (historyIndex < 80) {
            basePenaltyPercent = 75.0;
          } else if (historyIndex < 100) {
            basePenaltyPercent = 60.0;
          } else if (historyIndex < 150) {
            basePenaltyPercent = 40.0;
          } else {
            basePenaltyPercent = 20.0;
          }
        }

        // Adjust penalty based on play ratio
        double penaltyMultiplier = 1.0;
        if (playRatioInHistory < 0.25) {
          penaltyMultiplier = 0.3;
        } else if (playRatioInHistory < 0.5) {
          penaltyMultiplier = 0.5;
        } else if (playRatioInHistory < 0.8) {
          penaltyMultiplier = 0.8;
        }

        double adjustedPenaltyPercent = basePenaltyPercent * penaltyMultiplier;
        weight *= (1.0 - (adjustedPenaltyPercent / 100.0));
      }
    }

    // HIERARCHY 2: Global Skip Penalty
    if (item.type == _VirtualItemType.standalone) {
      final stats = skipStats[representative.song.filename];
      if (stats != null && stats.count >= 3 && stats.avgRatio <= 0.25) {
        weight *= stats.avgRatio;
      }
    } else {
      // For merge groups, check all songs
      for (final queueItem in item.items) {
        final stats = skipStats[queueItem.song.filename];
        if (stats != null && stats.count >= 3 && stats.avgRatio <= 0.25) {
          weight *= 0.5; // 50% penalty if any song in group is often skipped
          break;
        }
      }
    }

    // HIERARCHY 3: Mode-Specific Weights
    if (config.personality == ShufflePersonality.explorer) {
      if (maxPlayCount > 0) {
        final playRatio = groupPlayCount / maxPlayCount;
        if (playRatio <= 0.4) {
          double explorerReward = 1.0 + (1.0 - (playRatio / 0.4));
          weight *= explorerReward;
        }
      } else if (groupPlayCount == 0) {
        weight *= 2.0;
      }
    } else if (config.personality == ShufflePersonality.consistent) {
      int threshold = 10;
      if (maxPlayCount < 10) {
        threshold = max(1, (maxPlayCount * 0.7).floor());
      } else if (maxPlayCount < 20) {
        threshold = 5;
      }

      if (groupPlayCount >= threshold && groupPlayCount > 0) {
        weight *= 1.3;
      }
    } else if (config.personality == ShufflePersonality.custom) {
      // Custom mode: use user-defined weights (-99 to +99)
      // Convert -99..+99 to multiplier (0.01 to 1.99, with 0 = 1.0 neutral)
      double weightToMultiplier(int weight) {
        return 1.0 + (weight / 100.0); // -99 -> 0.01, 0 -> 1.0, +99 -> 1.99
      }

      // Apply least played weight for songs with low play count
      if (maxPlayCount > 0) {
        final playRatio = groupPlayCount / maxPlayCount;
        if (playRatio <= 0.4 && config.leastPlayedWeight != 0) {
          weight *= weightToMultiplier(config.leastPlayedWeight);
        }
      } else if (groupPlayCount == 0 && config.leastPlayedWeight != 0) {
        weight *= weightToMultiplier(config.leastPlayedWeight);
      }

      // Apply most played weight for songs in top 40% of play counts
      if (maxPlayCount > 0) {
        final playRatio = groupPlayCount / maxPlayCount;
        if (playRatio >= 0.6 && config.mostPlayedWeight != 0) {
          weight *= weightToMultiplier(config.mostPlayedWeight);
        }
      }
    }

    // HIERARCHY 4: Artist/Album Avoidance (all modes except Consistent)
    final bool isExplorer = config.personality == ShufflePersonality.explorer;
    final bool isDefault = config.personality == ShufflePersonality.defaultMode;
    final bool shouldAvoidArtist = isExplorer ||
        isDefault ||
        (isCustomMode && config.avoidRepeatingArtists);
    final bool shouldAvoidAlbum = isExplorer ||
        isDefault ||
        (isCustomMode && config.avoidRepeatingAlbums);

    if ((shouldAvoidArtist || shouldAvoidAlbum) && prev != null) {
      final prevSong = prev.representative.song;
      final currentSong = representative.song;

      // Check if in same merge group
      if (item.type == _VirtualItemType.mergeGroup &&
          prev.type == _VirtualItemType.mergeGroup &&
          item.groupId == prev.groupId) {
        weight *= 0.01; // 99% penalty for same merge group
      } else {
        // Artist avoidance
        if (shouldAvoidArtist) {
          if (currentSong.artist != 'Unknown Artist' &&
              prevSong.artist != 'Unknown Artist' &&
              currentSong.artist == prevSong.artist) {
            weight *= 0.5; // 50% penalty
          }
        }

        // Album avoidance
        if (shouldAvoidAlbum) {
          if (currentSong.album != 'Unknown Album' &&
              prevSong.album != 'Unknown Album' &&
              currentSong.album == prevSong.album) {
            weight *= 0.7; // 30% penalty
          }
        }
      }
    }

    // LOWER PRIORITY: Favorites and Suggest-Less (consider group as a whole)
    bool hasFavorite = false;
    bool hasSuggestLess = false;

    if (item.type == _VirtualItemType.mergeGroup) {
      for (final queueItem in item.items) {
        if (_isFavorite(queueItem.song.filename)) hasFavorite = true;
        if (_isSuggestLess(queueItem.song.filename)) hasSuggestLess = true;
      }
    } else {
      if (_isFavorite(representative.song.filename)) hasFavorite = true;
      if (_isSuggestLess(representative.song.filename)) hasSuggestLess = true;
    }

    if (hasFavorite) {
      if (config.personality == ShufflePersonality.consistent) {
        weight *= 1.4;
      } else if (config.personality == ShufflePersonality.explorer) {
        weight *= 1.12;
      } else if (config.personality == ShufflePersonality.custom) {
        // Convert -99..+99 to multiplier
        double weightToMultiplier(int weight) {
          return 1.0 + (weight / 100.0);
        }

        if (config.favoritesWeight != 0) {
          weight *= weightToMultiplier(config.favoritesWeight);
        }
      } else {
        weight *= config.favoriteMultiplier;
      }
    }

    if (hasSuggestLess) {
      if (config.personality == ShufflePersonality.custom &&
          config.suggestLessWeight != 0) {
        // Convert -99..+99 to multiplier (negative = penalty, positive = boost)
        double weightToMultiplier(int weight) {
          return 1.0 + (weight / 100.0);
        }

        weight *= weightToMultiplier(config.suggestLessWeight);
      } else {
        weight *= 0.2;
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
    _resetFading();

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
    _positionSubscription?.cancel();
    _sequenceSubscription?.cancel();
    _fadeTimer?.cancel();
    _player.dispose();
    shuffleNotifier.dispose();
  }
}

// Helper enum and class for merge group shuffle logic
enum _VirtualItemType { standalone, mergeGroup }

class _VirtualShuffleItem {
  final _VirtualItemType type;
  final List<QueueItem> items;
  final QueueItem representative;
  final String? groupId;

  _VirtualShuffleItem({
    required this.type,
    required this.items,
    required this.representative,
    this.groupId,
  });
}

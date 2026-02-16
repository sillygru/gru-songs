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

// Gap state persistence keys
const String _keyGapSongId = 'gap_current_song_id';
const String _keyGapResumeTimestamp = 'gap_resume_timestamp';
const String _keyGapIsActive = 'gap_is_active';

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
  bool _isInGap = false;
  bool _pausedByGap = false;
  String? _lastFadedFilename;
  String? _currentGapSongId;
  Timer? _fadeTimer;
  Timer? _gapTimer;
  DateTime? _gapStartTime;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<SequenceState?>? _sequenceSubscription;

  // Fade state tracking
  double _targetVolume = 1.0;
  DateTime? _fadeStartTime;
  double? _fadeDurationMs;

  // Feature coordination state
  bool _wasPausedByMute = false;

  // New stats counters
  double _foregroundDuration = 0.0;
  double _backgroundDuration = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
  final ValueNotifier<ShuffleState> shuffleStateNotifier = ValueNotifier(
    const ShuffleState(),
  );
  final ValueNotifier<List<QueueItem>> queueNotifier = ValueNotifier([]);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier(null);

  AudioPlayerManager(this._statsService, this._storageService, [this._ref]) {
    WidgetsBinding.instance.addObserver(this);
    _initStatsListeners();
    _initFadingListeners();
    _initPersistence();
    _initVolumeMonitoring();
    _restoreGapStateIfNeeded();
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

  void setUserData({
    List<String>? favorites,
    List<String>? suggestLess,
    List<String>? hidden,
    Map<String, List<String>>? mergedGroups,
  }) {
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
      final currentIndex = _player.currentIndex ?? 0;
      if (config.enabled) {
        await _applyShuffle(currentIndex);
      } else {
        _applyLinear(currentIndex);
      }
    }
  }

  Future<void> playSong(
    Song song, {
    List<Song>? contextQueue,
    String? playlistId,
    bool startPlaying = true,
    bool forceLinear = false,
  }) async {
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

    int originalIdx = _originalQueue.indexWhere(
      (item) => item.song.filename == song.filename,
    );
    if (originalIdx == -1) {
      _originalQueue.insert(0, QueueItem(song: song));
      originalIdx = 0;
    }

    final selectedItem = _originalQueue[originalIdx];

    if (_shuffleState.config.enabled && !forceLinear) {
      final otherItems = List<QueueItem>.from(_originalQueue)
        ..removeAt(originalIdx);
      final shuffledOthers = await _weightedShuffle(
        otherItems,
        lastItem: selectedItem,
      );
      _effectiveQueue = [selectedItem, ...shuffledOthers];
      await _rebuildQueue(initialIndex: 0, startPlaying: startPlaying);
    } else {
      _effectiveQueue = List.from(_originalQueue);
      await _rebuildQueue(
        initialIndex: originalIdx,
        startPlaying: startPlaying,
      );
    }

    _savePlaybackState();
  }

  void _initStatsListeners() {
    // Track previous playing state for manual pause detection
    bool wasPlaying = false;

    _player.playerStateStream.listen((state) {
      // Detect manual pause (user pressed pause button)
      // Don't cancel transitions if we are in a gap (expected pause)
      if (wasPlaying && !state.playing && !_isInGap && !_pausedByGap) {
        _handleManualIntervention();
      }

      // Handle user pressing play during gap - cancel the gap timer
      if (_isInGap && state.playing) {
        _cancelGap();
      }

      // Reset pausedByGap after the state settles
      if (!wasPlaying && !state.playing) {
        _pausedByGap = false;
      }

      wasPlaying = state.playing;

      if (state.playing) {
        _playStartTime ??= DateTime.now();
      } else if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = null;
        _flushStats(eventType: 'listen');
      }
      if (state.processingState == ProcessingState.completed) {
        _isCompleting = true;
        _flushStats(eventType: 'complete');
      }
    });

    // Listen for seek operations to cancel fade out
    _player.positionStream.listen((position) {
      if (_isFadingOut) {
        final totalDuration = _player.duration;
        if (totalDuration != null && _ref != null) {
          final remaining = totalDuration - position;
          final settings = _ref!.read(settingsProvider);
          final fadeOutDuration = settings.fadeOutDuration;
          if (fadeOutDuration > 0 &&
              remaining.inMilliseconds > fadeOutDuration * 1000 + 500) {
            // User seeked back, cancel fade
            _cancelTransitions();
          }
        }
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

        // Stats tracking
        if (_currentSongFilename != null &&
            _currentSongFilename != newFilename) {
          if (!_isCompleting) {
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
            _preExtractNextColor();
          }
        }
      }
    });
  }

  // ==================== FADE AND GAP LOGIC ====================

  void _initFadingListeners() {
    _positionSubscription = _player.positionStream.listen((position) {
      if (_ref == null) return;
      final settings = _ref!.read(settingsProvider);

      final totalDuration = _player.duration;
      if (totalDuration == null) return;

      // Minimum 30 second song for any transitions
      if (totalDuration.inSeconds < 30) return;

      final remaining = totalDuration - position;

      // Handle gap mode - pause before end, resume after delay
      if (settings.delayDuration > 0 && !_isInGap && _player.playing) {
        _handleGapTrigger(
          remaining: remaining,
          delayDuration: settings.delayDuration,
        );
      }

      // Handle fade mode
      if ((settings.fadeOutDuration > 0 || settings.fadeInDuration > 0) &&
          _player.playing) {
        _handleFadeMode(
          remaining: remaining,
          position: position,
          totalDuration: totalDuration,
          fadeOutDuration: settings.fadeOutDuration,
        );
      }

      // Reset fade if user seeks back
      if (_isFadingOut) {
        final fadeOutMs = settings.fadeOutDuration * 1000;
        if (remaining.inMilliseconds > fadeOutMs) {
          _isFadingOut = false;
          if (!_isFadingIn) {
            _setVolumeWithSafety(1.0);
          }
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
          // Reset gap state on new song
          _isInGap = false;
          _currentGapSongId = null;
          _gapTimer?.cancel();
          _isFadingOut = false;

          // Always reset volume on song change
          _setVolumeWithSafety(1.0);

          // Handle fade in for new song
          if (settings.fadeInDuration > 0) {
            _startFadeIn(settings.fadeInDuration);
          }
        }
      }
    });

    // Handle completion - just ensure volume is reset
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _setVolumeWithSafety(1.0);
        _isFadingOut = false;
      }
    });
  }

  void _generateOfflineNext() async {
    // Pick a random song from _allSongs using local weights
    if (_allSongs.isEmpty) return;

    final currentIndex = _player.currentIndex ?? -1;
    if (currentIndex < 0) return;

    final currentItem = _effectiveQueue[currentIndex];
    final existingIds = _effectiveQueue.map((e) => e.song.filename).toSet();

    // Filter candidates
    final List<QueueItem> candidateItems;
    if (_isRestrictedToOriginal) {
      candidateItems = _originalQueue
          .where((q) => !existingIds.contains(q.song.filename))
          .toList();
    } else {
      candidateItems = _allSongs
          .where((s) => !existingIds.contains(s.filename))
          .map((s) => QueueItem(song: s))
          .toList();
    }

    if (candidateItems.isEmpty) return;
    final shuffled = await _weightedShuffle(
      candidateItems,
      lastItem: currentItem,
    );

    if (shuffled.isNotEmpty) {
      final nextItem = shuffled.first;
      _effectiveQueue.add(nextItem);
      final source = await _createAudioSource(nextItem);
      await _player.addAudioSource(source);
      _updateQueueNotifier();
    }
  }

  Future<void> _initPersistence() async {
    // Load shuffle state
    final savedShuffleJson = await _storageService.loadShuffleState();
    if (savedShuffleJson != null) {
      _shuffleState = ShuffleState.fromJson(savedShuffleJson);
      shuffleStateNotifier.value = _shuffleState;
      shuffleNotifier.value = _shuffleState.config.enabled;
    }
  }

  void _initVolumeMonitoring() {
    if (_ref != null) {
      _volumeMonitorService = VolumeMonitorService(
        onVolumeZero: () {
          final currentSettings = _ref!.read(settingsProvider);
          if (currentSettings.autoPauseOnVolumeZero && _player.playing) {
            _wasPausedByMute = true;
            _player.pause();
          }
        },
        onVolumeRestored: () {
          final currentSettings = _ref!.read(settingsProvider);
          if (currentSettings.autoPauseOnVolumeZero &&
              currentSettings.autoResumeOnVolumeRestore &&
              _wasPausedByMute) {
            _wasPausedByMute = false;
            // If in gap, wait for gap to complete
            if (!_isInGap) {
              _player.play();
            }
          }
        },
      );
      _volumeMonitorService?.initialize();

      _ref!.listen(settingsProvider, (previous, next) {
        if (previous?.autoPauseOnVolumeZero != next.autoPauseOnVolumeZero) {
          _volumeMonitorService
              ?.setAutoPauseEnabled(next.autoPauseOnVolumeZero);
        }
      });

      final initialSettings = _ref!.read(settingsProvider);
      _volumeMonitorService?.setAutoPauseEnabled(
        initialSettings.autoPauseOnVolumeZero,
      );
    }
  }

  void _handleGapTrigger({
    required Duration remaining,
    required double delayDuration,
  }) {
    // Trigger gap when 1 second remains
    if (remaining.inMilliseconds <= 1000 && remaining.inMilliseconds > 0) {
      _triggerSimpleGap(delayDuration: delayDuration);
    }
  }

  void _triggerSimpleGap({required double delayDuration}) {
    if (_isInGap) return;

    final currentItem = _player.sequenceState?.currentSource?.tag;
    if (currentItem is! MediaItem) return;

    _currentGapSongId = currentItem.id;
    _isInGap = true;
    _pausedByGap = true;

    // Pause playback (1 second before end)
    _player.pause();

    // Schedule resume after gap duration
    final delayMs = (delayDuration * 1000).toInt();
    _gapTimer = Timer(Duration(milliseconds: delayMs), () {
      _resumeAfterGap(expectedSongId: currentItem.id);
    });
  }

  void _resumeAfterGap({required String expectedSongId}) {
    if (!_isInGap) return;

    // Clear gap state
    _isInGap = false;
    _pausedByGap = false;
    _currentGapSongId = null;
    _gapTimer = null;

    // Verify we're still on the same song
    final currentItem = _player.sequenceState?.currentSource?.tag;
    if (currentItem is! MediaItem || currentItem.id != expectedSongId) {
      // User skipped/changed song during gap
      return;
    }

    // Skip to next song after gap
    if (_player.hasNext) {
      _player.seekToNext();
    }
    if (!_wasPausedByMute) {
      _player.play();
    }
  }

  void _handleFadeMode({
    required Duration remaining,
    required Duration position,
    required Duration totalDuration,
    required double fadeOutDuration,
  }) {
    final fadeOutMs = (fadeOutDuration * 1000).toInt();

    if (fadeOutMs > 0 &&
        remaining.inMilliseconds <= fadeOutMs &&
        remaining.inMilliseconds > 0 &&
        !_isFadingOut) {
      _isFadingOut = true;
    }

    if (_isFadingOut) {
      final progress = remaining.inMilliseconds / fadeOutMs;
      final curvedVolume = _fadeOutCurve(progress.clamp(0.0, 1.0));
      _setVolumeWithSafety(curvedVolume);
    }
  }

  // Exponential fade out curve (sounds natural to human ears)
  double _fadeOutCurve(double linearProgress) {
    // Exponential decay: volume drops faster at the end
    // linearProgress: 1.0 -> 0.0 (remaining time ratio)
    // Returns: curved volume from 1.0 -> 0.0
    return pow(linearProgress, 2.0).toDouble();
  }

  // Exponential fade in curve (sounds natural to human ears)
  double _fadeInCurve(double linearProgress) {
    // Exponential growth: volume rises slower at the start
    // linearProgress: 0.0 -> 1.0 (elapsed time ratio)
    // Returns: curved volume from 0.0 -> 1.0
    return pow(linearProgress, 0.5).toDouble();
  }

  void _startFadeIn(double duration) {
    _fadeTimer?.cancel();
    _isFadingIn = true;
    _fadeDurationMs = duration * 1000;
    _fadeStartTime = DateTime.now();
    _targetVolume = 1.0;

    _setVolumeWithSafety(0.0);

    _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_fadeStartTime == null || _fadeDurationMs == null) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_fadeStartTime!).inMilliseconds;
      final targetMs = _fadeDurationMs!;

      if (elapsed >= targetMs) {
        _setVolumeWithSafety(1.0);
        _isFadingIn = false;
        _fadeStartTime = null;
        _fadeDurationMs = null;
        timer.cancel();
      } else {
        final linearProgress = elapsed / targetMs;
        final curvedVolume = _fadeInCurve(linearProgress);
        _setVolumeWithSafety(curvedVolume);
      }
    });
  }

  void _setVolumeWithSafety(double volume) {
    _targetVolume = volume.clamp(0.0, 1.0);
    try {
      _player.setVolume(_targetVolume);
    } catch (e) {
      debugPrint('AudioPlayerManager: Failed to set volume: $e');
    }
  }

  void _resetFading() {
    _fadeTimer?.cancel();
    _isFadingIn = false;
    _isFadingOut = false;
    _fadeStartTime = null;
    _fadeDurationMs = null;
    _targetVolume = 1.0;
    _setVolumeWithSafety(1.0);
  }

  void _cancelTransitions() {
    _cancelGap();
    _fadeTimer?.cancel();
    _isFadingIn = false;
    _isFadingOut = false;
    _fadeStartTime = null;
    _fadeDurationMs = null;
    _targetVolume = 1.0;
    _setVolumeWithSafety(1.0);
  }

  void _cancelGap() {
    _isInGap = false;
    _pausedByGap = false;
    _currentGapSongId = null;
    _gapStartTime = null;
    _gapTimer?.cancel();
    _clearGapState();
  }

  void _handleManualIntervention() {
    // User manually paused - cancel any ongoing transitions
    _cancelTransitions();
  }

  // ==================== GAP STATE PERSISTENCE ====================

  Future<void> _persistGapState({
    required String songId,
    required int delayMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumeTimestamp = DateTime.now().millisecondsSinceEpoch + delayMs;

      await prefs.setString(_keyGapSongId, songId);
      await prefs.setInt(_keyGapResumeTimestamp, resumeTimestamp);
      await prefs.setBool(_keyGapIsActive, true);
    } catch (e) {
      debugPrint('AudioPlayerManager: Failed to persist gap state: $e');
    }
  }

  Future<void> _clearGapState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyGapSongId);
      await prefs.remove(_keyGapResumeTimestamp);
      await prefs.remove(_keyGapIsActive);
    } catch (e) {
      debugPrint('AudioPlayerManager: Failed to clear gap state: $e');
    }
  }

  Future<void> _restoreGapStateIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_keyGapIsActive) ?? false;

      if (!isActive) return;

      final songId = prefs.getString(_keyGapSongId);
      final resumeTimestamp = prefs.getInt(_keyGapResumeTimestamp);

      if (songId == null || resumeTimestamp == null) {
        await _clearGapState();
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final remainingMs = resumeTimestamp - now;

      if (remainingMs <= 0) {
        // Gap already expired, clear state
        await _clearGapState();
        return;
      }

      // We're still in a gap from before
      // Check if we're on the same song
      final currentItem = _player.sequenceState?.currentSource?.tag;
      if (currentItem is! MediaItem || currentItem.id != songId) {
        await _clearGapState();
        return;
      }

      // Restore gap state
      _currentGapSongId = songId;
      _isInGap = true;

      // Schedule resume - just_audio will auto-advance to next song
      _gapTimer = Timer(Duration(milliseconds: remainingMs), () {
        _resumeAfterGap(expectedSongId: songId);
      });
    } catch (e) {
      debugPrint('AudioPlayerManager: Failed to restore gap state: $e');
    }
  }

  // ==================== LIFECYCLE ====================

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
      _statsService.flush();
    }

    final isBackground = state != AppLifecycleState.resumed;
    _statsService.setBackground(isBackground);

    _appLifecycleState = state;
  }

  // ==================== STATS & SHUFFLE ====================

  void _preExtractNextColor() {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null || _effectiveQueue.isEmpty) return;

    final nextIndex = currentIndex + 1;
    if (nextIndex >= _effectiveQueue.length) return;

    final nextSong = _effectiveQueue[nextIndex].song;
    if (nextSong.coverUrl != null) {
      ColorExtractionService.extractColor(nextSong.coverUrl);
    }
  }

  Future<ShuffleState?> syncShuffleState() async {
    return _shuffleState;
  }

  Future<void> _saveShuffleState() async {
    await _storageService.saveShuffleState(_shuffleState.toJson());
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

    String finalEventType = eventType;

    if (totalLength > 0) {
      final double ratio = finalDuration / totalLength;
      final double remaining = totalLength - finalDuration;

      if (remaining <= 10.0 || ratio >= 1.0) {
        finalEventType = 'complete';
      } else if (ratio < 0.10) {
        finalEventType = 'skip';
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

      if (finalEventType == 'complete' || finalDuration > 5.0) {
        _addToShuffleHistory(_currentSongFilename!);
      }
    }
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    if (eventType == 'skip' || eventType == 'complete') {
      _playStartTime = null;
      _statsService.flush();
    } else {
      if (_playStartTime != null) _playStartTime = DateTime.now();
    }
  }

  void _addToShuffleHistory(String filename) {
    // History is tracked via database play events
  }

  // ==================== INIT & QUEUE ====================

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    _allSongs = songs;
    _songMap = {for (var s in songs) s.filename: s};
    _isRestrictedToOriginal = false;
    await _player.setShuffleModeEnabled(false);

    await DatabaseService.instance.init();

    final savedState = await _storageService.loadPlaybackState();

    if (savedState != null) {
      try {
        final List<dynamic> effJson = savedState['last_effective_queue'] ?? [];
        final List<dynamic> origJson = savedState['last_original_queue'] ?? [];

        _effectiveQueue = effJson.expand((j) {
          try {
            final queueItem = QueueItem.fromJson(j);
            if (queueItem.song.url.isNotEmpty) {
              final file = File(queueItem.song.url);
              if (file.existsSync()) {
                return [queueItem];
              }
            }
            return <QueueItem>[];
          } catch (e) {
            return <QueueItem>[];
          }
        }).toList();

        _originalQueue = origJson.expand((j) {
          try {
            final queueItem = QueueItem.fromJson(j);
            if (queueItem.song.url.isNotEmpty) {
              final file = File(queueItem.song.url);
              if (file.existsSync()) {
                return [queueItem];
              }
            }
            return <QueueItem>[];
          } catch (e) {
            return <QueueItem>[];
          }
        }).toList();

        if (_effectiveQueue.isNotEmpty || _originalQueue.isNotEmpty) {
          _isRestrictedToOriginal =
              savedState['is_restricted_to_original'] ?? false;
          _currentPlaylistId = savedState['current_playlist_id'];

          final savedPositionMs = savedState['last_position_ms'] ?? 0;
          final lastSongFilename = savedState['last_song_filename'];

          int initialIndex = 0;
          Duration? resumePosition;

          if (lastSongFilename != null) {
            initialIndex = _effectiveQueue.indexWhere(
              (item) => item.song.filename == lastSongFilename,
            );
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
            initialPosition: resumePosition,
          );
          return;
        }
      } catch (e) {
        // Ignore
      }
    }

    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _effectiveQueue = List.from(_originalQueue);

    int initialIndex = 0;
    if (autoSelect && songs.isNotEmpty) {
      initialIndex = Random().nextInt(songs.length);
    }
    await _rebuildQueue(initialIndex: initialIndex, startPlaying: false);
  }

  void refreshSongs(List<Song> newSongs) {
    _allSongs = newSongs.where((s) => !_isHidden(s.filename)).toList();
    _songMap = {for (var s in _allSongs) s.filename: s};

    final currentIdx = _player.currentIndex;
    final currentItemBefore =
        (currentIdx != null && currentIdx < _effectiveQueue.length)
            ? _effectiveQueue[currentIdx]
            : null;

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

      final shuffled = await _weightedShuffle(
        candidateItems,
        lastItem: currentItem,
      );

      _effectiveQueue = [...prefix, ...priorityItems, ...shuffled];
      await _rebuildQueue(
        initialIndex: currentIndex,
        startPlaying: _player.playing,
      );
      return;
    }

    _applyLinear(currentIndex);
  }

  void _applyLinear(int currentIndex) {
    if (currentIndex >= _originalQueue.length) return;

    final prefix = _originalQueue.sublist(0, currentIndex + 1);
    final suffix = _originalQueue.sublist(currentIndex + 1);

    _effectiveQueue = [...prefix, ...suffix];
    _rebuildQueue(initialIndex: currentIndex, startPlaying: _player.playing);
  }

  Future<AudioSource> _createAudioSource(QueueItem item) async {
    final song = item.song;
    final Uri audioUri = Uri.file(song.url);

    Uri? artUri;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      artUri = Uri.file(song.coverUrl!);
    }

    // Keep notification during gap to prevent service death
    final bool keepNotification =
        _ref != null && _ref!.read(settingsProvider).delayDuration > 0;

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
          'hasLyrics': song.hasLyrics,
          'remoteUrl': song.url,
          'queueId': item.queueId,
          'isPriority': item.isPriority,
          'androidStopForegroundOnPause': !keepNotification,
          'audioPath': song.url,
        },
      ),
    );
  }

  void _updateQueueNotifier() {
    queueNotifier.value = List.from(_effectiveQueue);
  }

  Future<void> shuffleAndPlay(
    List<Song> songs, {
    bool isRestricted = false,
  }) async {
    if (songs.isEmpty) return;

    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: true),
    );
    shuffleNotifier.value = true;
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();

    final randomIdx = Random().nextInt(songs.length);

    if (isRestricted) {
      await playSong(songs[randomIdx], contextQueue: songs, startPlaying: true);
    } else {
      _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      _isRestrictedToOriginal = false;
      await playSong(songs[randomIdx], startPlaying: true);
    }
  }

  Future<void> toggleShuffle() async {
    final isShuffle = !shuffleNotifier.value;
    shuffleNotifier.value = isShuffle;
    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: isShuffle),
    );
    shuffleStateNotifier.value = _shuffleState;
    updateShuffleConfig(_shuffleState.config);
  }

  Future<void> replaceQueue(
    List<Song> songs, {
    String? playlistId,
    bool forceLinear = false,
  }) async {
    if (songs.isEmpty) return;
    _currentPlaylistId = playlistId;

    final currentSong = currentSongNotifier.value;
    final isPlaying = _player.playing;

    if (forceLinear) {
      _resetFading();
      await _player.setShuffleModeEnabled(false);

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

      if (currentSong != null && isPlaying) {
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
    final shuffledNormal = await _weightedShuffle(
      normalItems,
      lastItem: currentItem,
    );

    _effectiveQueue = [currentItem, ...priorityItems, ...shuffledNormal];
    await _rebuildQueue(
      initialIndex: 0,
      startPlaying: _player.playing,
    );
  }

  Future<List<QueueItem>> _weightedShuffle(
    List<QueueItem> items, {
    QueueItem? lastItem,
  }) async {
    if (items.isEmpty) return [];

    final playCounts = await DatabaseService.instance.getPlayCounts();
    final skipStats = await DatabaseService.instance.getSkipStats();
    final playHistory = await DatabaseService.instance
        .getPlayHistory(limit: _shuffleState.config.historyLimit);

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

    final virtualItems = <_VirtualShuffleItem>[];

    for (final item in standaloneItems) {
      virtualItems.add(_VirtualShuffleItem(
        type: _VirtualItemType.standalone,
        items: [item],
        representative: item,
      ));
    }

    for (final entry in mergeGroups.entries) {
      virtualItems.add(_VirtualShuffleItem(
        type: _VirtualItemType.mergeGroup,
        items: entry.value,
        representative: entry.value.first,
        groupId: entry.key,
      ));
    }

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

  _VirtualShuffleItem? _createVirtualItemFromQueueItem(
    QueueItem item,
    Map<String, List<QueueItem>> mergeGroups,
  ) {
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

  String? _getMergedGroupId(String filename) {
    for (final entry in _mergedGroups.entries) {
      if (entry.value.contains(filename)) {
        return entry.key;
      }
    }
    return null;
  }

  QueueItem? _selectSongFromVirtualItem(_VirtualShuffleItem virtualItem) {
    if (virtualItem.items.length == 1) {
      return virtualItem.items.first;
    }

    final weights = virtualItem.items.map((item) {
      double weight = 1.0;
      if (_isFavorite(item.song.filename)) {
        weight *= 2.0;
      }
      if (_isSuggestLess(item.song.filename)) {
        weight *= 0.2;
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

    int groupPlayCount = 0;
    if (item.type == _VirtualItemType.mergeGroup) {
      for (final queueItem in item.items) {
        groupPlayCount += playCounts[queueItem.song.filename] ?? 0;
      }
    } else {
      groupPlayCount = playCounts[representative.song.filename] ?? 0;
    }

    final bool isConsistentMode =
        config.personality == ShufflePersonality.consistent;
    final bool isCustomMode = config.personality == ShufflePersonality.custom;
    final bool shouldAvoidRepeatingSongs =
        isCustomMode ? config.avoidRepeatingSongs : !isConsistentMode;

    if (shouldAvoidRepeatingSongs && playHistory.isNotEmpty) {
      int historyIndex = -1;
      double playRatioInHistory = 0.0;

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

        if (isConsistentMode) {
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
          if (historyIndex < 10) {
            basePenaltyPercent = 95.0;
          } else if (historyIndex < 20) {
            basePenaltyPercent = 90.0;
          } else if (historyIndex < 30) {
            basePenaltyPercent = 80.0;
          } else if (historyIndex < 40) {
            basePenaltyPercent = 70.0;
          } else if (historyIndex < 50) {
            basePenaltyPercent = 60.0;
          } else if (historyIndex < 60) {
            basePenaltyPercent = 50.0;
          } else if (historyIndex < 80) {
            basePenaltyPercent = 40.0;
          } else if (historyIndex < 100) {
            basePenaltyPercent = 30.0;
          } else if (historyIndex < 120) {
            basePenaltyPercent = 20.0;
          } else if (historyIndex < 150) {
            basePenaltyPercent = 10.0;
          } else {
            basePenaltyPercent = 5.0;
          }
        }

        double penaltyMultiplier = basePenaltyPercent / 100.0;
        if (playRatioInHistory >= 0.9) {
          penaltyMultiplier *= 1.2;
        }

        weight *= (1.0 - penaltyMultiplier.clamp(0.0, 0.95));
      }
    }

    if (prev != null) {
      final prevArtist = prev.representative.song.artist.toLowerCase().trim();
      final currentArtist = representative.song.artist.toLowerCase().trim();

      if (prevArtist.isNotEmpty &&
          currentArtist.isNotEmpty &&
          prevArtist == currentArtist) {
        weight *= 0.1;
      }

      final prevAlbum = prev.representative.song.album.toLowerCase().trim();
      final currentAlbum = representative.song.album.toLowerCase().trim();

      if (prevAlbum.isNotEmpty &&
          currentAlbum.isNotEmpty &&
          prevAlbum == currentAlbum) {
        weight *= 0.3;
      }
    }

    if (isCustomMode) {
      // Apply favorites weight (-99 to +99, convert to multiplier)
      final favoriteBoost = config.favoritesWeight / 100.0;
      final suggestLessPenalty = -config.suggestLessWeight / 100.0;

      if (item.type == _VirtualItemType.mergeGroup) {
        bool hasFavorite = false;
        bool hasSuggestLess = false;

        for (final queueItem in item.items) {
          if (_isFavorite(queueItem.song.filename)) hasFavorite = true;
          if (_isSuggestLess(queueItem.song.filename)) hasSuggestLess = true;
        }

        if (hasFavorite && favoriteBoost != 0) {
          weight *= (1.0 + favoriteBoost);
        }
        if (hasSuggestLess && suggestLessPenalty != 0) {
          weight *= (1.0 + suggestLessPenalty);
        }
      } else {
        if (_isFavorite(representative.song.filename) && favoriteBoost != 0) {
          weight *= (1.0 + favoriteBoost);
        }
        if (_isSuggestLess(representative.song.filename) &&
            suggestLessPenalty != 0) {
          weight *= (1.0 + suggestLessPenalty);
        }
      }

      // Apply skip score adjustment in custom mode
      if (item.type == _VirtualItemType.mergeGroup) {
        double totalSkipRatio = 0;
        int count = 0;
        for (final queueItem in item.items) {
          final skipStat = skipStats[queueItem.song.filename];
          if (skipStat != null && skipStat.count > 0) {
            totalSkipRatio += skipStat.avgRatio;
            count++;
          }
        }
        if (count > 0) {
          final avgSkipRatio = totalSkipRatio / count;
          if (avgSkipRatio < 0.3) {
            weight *= 0.5;
          } else if (avgSkipRatio > 0.7) {
            weight *= 1.2;
          }
        }
      } else {
        final skipStat = skipStats[representative.song.filename];
        if (skipStat != null && skipStat.count > 0) {
          if (skipStat.avgRatio < 0.3) {
            weight *= 0.5;
          } else if (skipStat.avgRatio > 0.7) {
            weight *= 1.2;
          }
        }
      }
    }

    if (!isConsistentMode) {
      if (maxPlayCount > 0 && groupPlayCount > 0) {
        final playCountRatio = groupPlayCount / maxPlayCount;
        final playCountPenalty = playCountRatio * 0.3;
        weight *= (1.0 - playCountPenalty);
      }
    }

    return weight.clamp(0.01, double.infinity);
  }

  Future<void> _rebuildQueue({
    int? initialIndex,
    bool startPlaying = true,
    Duration? initialPosition,
  }) async {
    if (_effectiveQueue.isEmpty) return;
    _resetFading();

    final targetIndex = initialIndex ?? _player.currentIndex ?? 0;
    final currentItem = (targetIndex < _effectiveQueue.length)
        ? _effectiveQueue[targetIndex]
        : null;

    final sequenceState = _player.sequenceState;
    final currentMediaItem = sequenceState.currentSource?.tag as MediaItem?;
    final currentPosition = _player.position;

    Duration position = Duration.zero;
    if (initialPosition != null) {
      position = initialPosition;
    } else if (currentMediaItem != null && currentItem != null) {
      if (currentMediaItem.id == currentItem.song.filename) {
        position = currentPosition;
      }
    }

    final sources = await Future.wait(
      _effectiveQueue.map((item) => _createAudioSource(item)),
    );
    await _player.setAudioSources(
      sources,
      initialIndex: targetIndex,
      initialPosition: position,
    );

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

  Future<void> clearUpcoming() async {
    final currentIndex = _player.currentIndex ?? -1;
    if (currentIndex < 0) return;

    if (currentIndex >= _effectiveQueue.length - 1) return;

    // Remove items from the end to avoid index shifts
    for (int i = _effectiveQueue.length - 1; i > currentIndex; i--) {
      _effectiveQueue.removeAt(i);
      await _player.removeAudioSourceAt(i);
    }

    _updateQueueNotifier();
    _savePlaybackState();
  }

  Future<void> togglePriority(int index) async {
    if (index < 0 || index >= _effectiveQueue.length) return;

    final item = _effectiveQueue[index];
    final newValue = !item.isPriority;
    final updatedItem = item.copyWith(isPriority: newValue);

    // Always remove first to prepare for move/update
    _effectiveQueue.removeAt(index);
    await _player.removeAudioSourceAt(index);

    int targetIndex = index;
    if (newValue) {
      // Pinning: Move to the very next position in queue
      final currentIndex = _player.currentIndex ?? -1;
      targetIndex = currentIndex + 1;
    }

    _effectiveQueue.insert(targetIndex, updatedItem);
    final source = await _createAudioSource(updatedItem);
    await _player.insertAudioSource(targetIndex, source);

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
    _gapTimer?.cancel();
    _clearGapState();
    _player.dispose();
    shuffleNotifier.dispose();
  }
}

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

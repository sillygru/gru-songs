import 'package:flutter/widgets.dart'; // For AppLifecycleListener
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:async'; // For Timer
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/queue_snapshot.dart';
import '../models/shuffle_config.dart';
import '../domain/services/shuffle_weight_service.dart';
import '../domain/services/queue_ops.dart' as queue_ops;
import 'stats_service.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'ffmpeg_service.dart';
import 'file_manager_service.dart';
import 'notification_cover_warmer.dart';
import 'volume_monitor_service.dart';
import 'color_extraction_service.dart';
import '../providers/theme_provider.dart';
import '../providers/queue_history_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/providers.dart';

// Gap state persistence keys
const String _keyGapSongId = 'gap_current_song_id';
const String _keyGapResumeTimestamp = 'gap_resume_timestamp';
const String _keyGapIsActive = 'gap_is_active';

// Cache limits for foreground/background
const int _foregroundCacheSize = 250;
const int _foregroundCacheBytes = 40 * 1024 * 1024; // 40MB
const int _backgroundCacheSize = 50;
const int _backgroundCacheBytes = 10 * 1024 * 1024; // 10MB

enum PlaybackMediaMode { audio, video }

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

  // Active queue snapshot ID for auto-save tracking
  String? _currentQueueSnapshotId;

  // Pending queue replacement (fires when current song ends)
  List<Song>? _pendingQueueSongs;
  String? _pendingQueuePlaylistId;
  final ValueNotifier<bool> pendingQueueNotifier = ValueNotifier(false);

  // User data for weighting (Fallback / Offline)
  // O(1) lookup sets for membership checks (shuffle weighting path is hot).
  Set<String> _favoriteKeys = const <String>{};
  Set<String> _suggestLessKeys = const <String>{};
  Set<String> _hiddenKeys = const <String>{};

  // Merged song groups for shuffle weighting
  Map<String, List<String>> _mergedGroups = {};
  // Filename -> groupId lookup, rebuilt on setUserData().
  Map<String, String> _filenameToGroupId = const <String, String>{};

  // Shuffle state
  ShuffleState _shuffleState = const ShuffleState();

  // Cache DB query results across rapid shuffle calls
  Map<String, int>? _cachedPlayCounts;
  Map<String, ({int count, double avgRatio})>? _cachedSkipStats;
  List<
      ({
        String filename,
        double timestamp,
        double playRatio,
        String eventType
      })>? _cachedPlayHistory;
  DateTime? _shuffleCacheTimestamp;
  static const Duration _shuffleCacheDuration = Duration(seconds: 30);

  // Stats tracking state
  String? _currentSongFilename;
  String? _currentPlaylistId;
  DateTime? _playStartTime;
  bool _isCompleting = false;

  // Previous session tracking for ignoring quick skips of resumed songs
  String? _previousSessionSongFilename;
  bool _isResumedFromPreviousSession = false;
  double? _pendingResumedSongStartSec;

  // Session-only first-song baseline tracking (RAM only)
  bool _sessionFirstSongCaptured = false;
  String? _sessionFirstSongFilename;
  double? _sessionFirstSongStartSec;

  // Volume monitoring
  VolumeMonitorService? _volumeMonitorService;

  // Fading and delay state
  bool _isFadingOut = false;
  bool _isInGap = false;
  bool _pausedByGap = false;
  String? _lastFadedFilename;
  Timer? _fadeTimer;
  Timer? _gapTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<SequenceState?>? _sequenceSubscription;
  final List<StreamSubscription<dynamic>> _trackedSubscriptions = [];
  SettingsState? _cachedSettings;
  Future<void> _queueMutationChain = Future<void>.value();
  Timer? _playbackStateSaveTimer;
  static const Duration _playbackStateSaveInterval =
      Duration(milliseconds: 750);

  // Guards deliberate queue mutations from the sequence-sync listener. While
  // this is > 0 the manager is itself rewriting the player's sources, so the
  // listener must not rebuild _effectiveQueue from a transient half-mutated
  // sequence. The sync exists only to catch changes made *outside* the app
  // (notification / headset actions).
  int _playerMutationDepth = 0;

  // Play/pause fade state (separate from track-transition fades)
  // ignore: unused_field
  bool _isPlayPauseFading = false;
  bool _isPausingByFade = false;
  Timer? _playPauseFadeTimer;

  // Fade state tracking
  double _targetVolume = 1.0;
  DateTime? _fadeStartTime;
  double? _fadeDurationMs;
  bool _holdMutedUntilNextTrack = false;

  // Feature coordination state
  bool _wasPausedByMute = false;
  bool _isGeneratingNext = false;

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
  final ValueNotifier<bool> playingNotifier = ValueNotifier(false);
  final ValueNotifier<PlaybackMediaMode> preferredMediaModeNotifier =
      ValueNotifier(PlaybackMediaMode.audio);
  final ValueNotifier<PlaybackMediaMode> effectiveMediaModeNotifier =
      ValueNotifier(PlaybackMediaMode.audio);

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
  PlaybackMediaMode get preferredMediaMode => preferredMediaModeNotifier.value;
  PlaybackMediaMode get effectiveMediaMode => effectiveMediaModeNotifier.value;

  Future<void> setPreferredMediaMode(PlaybackMediaMode mode) async {
    preferredMediaModeNotifier.value = mode;
    _updateEffectivePlaybackMode();
    await savePlaybackState();
  }

  PlaybackMediaMode _resolveEffectiveMode(Song? song) {
    if (preferredMediaModeNotifier.value == PlaybackMediaMode.video &&
        song?.hasVideo == true) {
      return PlaybackMediaMode.video;
    }
    return PlaybackMediaMode.audio;
  }

  void _updateEffectivePlaybackMode([Song? song]) {
    final currentSong = song ?? currentSongNotifier.value;
    effectiveMediaModeNotifier.value = _resolveEffectiveMode(currentSong);
  }

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
    final lower = filename.toLowerCase();
    return _favoriteKeys.contains(lower) ||
        _favoriteKeys.contains(p.basename(lower));
  }

  bool _isSuggestLess(String filename) {
    final lower = filename.toLowerCase();
    return _suggestLessKeys.contains(lower) ||
        _suggestLessKeys.contains(p.basename(lower));
  }

  bool _isHidden(String filename) {
    final lower = filename.toLowerCase();
    return _hiddenKeys.contains(lower) ||
        _hiddenKeys.contains(p.basename(lower));
  }

  void setUserData({
    List<String>? favorites,
    List<String>? suggestLess,
    List<String>? hidden,
    Map<String, List<String>>? mergedGroups,
  }) {
    if (favorites != null) {
      _favoriteKeys = _buildFilenameKeys(favorites);
    }
    if (suggestLess != null) {
      _suggestLessKeys = _buildFilenameKeys(suggestLess);
    }
    if (hidden != null) {
      _hiddenKeys = _buildFilenameKeys(hidden);
    }
    if (mergedGroups != null) {
      _mergedGroups = mergedGroups;
      _filenameToGroupId = _buildFilenameToGroupId(mergedGroups);
    }
    _invalidateShuffleCache();
  }

  void _invalidateShuffleCache() {
    _cachedPlayCounts = null;
    _cachedSkipStats = null;
    _cachedPlayHistory = null;
    _shuffleCacheTimestamp = null;
  }

  static Set<String> _buildFilenameKeys(List<String> filenames) {
    if (filenames.isEmpty) return const <String>{};
    final keys = <String>{};
    for (final f in filenames) {
      keys.add(f.toLowerCase());
      keys.add(p.basename(f).toLowerCase());
    }
    return keys;
  }

  static Map<String, String> _buildFilenameToGroupId(
      Map<String, List<String>> groups) {
    if (groups.isEmpty) return const <String, String>{};
    final map = <String, String>{};
    for (final entry in groups.entries) {
      for (final filename in entry.value) {
        map[filename] = entry.key;
      }
    }
    return map;
  }

  List<String> _getMergedSiblings(String filename) {
    for (final group in _mergedGroups.values) {
      if (group.contains(filename)) {
        return group.where((f) => f != filename).toList();
      }
    }
    return [];
  }

  int _findSongInQueue(String filename, {bool checkMergedSiblings = false}) {
    final queueFilenames = _effectiveQueue.map((e) => e.song.filename).toList();
    final idx = queueFilenames.indexOf(filename);
    if (idx != -1) return idx;
    if (checkMergedSiblings) {
      final siblings = _getMergedSiblings(filename);
      for (final sibling in siblings) {
        final siblingIdx = queueFilenames.indexOf(sibling);
        if (siblingIdx != -1) return siblingIdx;
      }
    }
    return -1;
  }

  Future<void> updateShuffleConfig(
    ShuffleConfig config, {
    bool applyToCurrentQueue = true,
    bool createSnapshotOnQueueApply = false,
  }) async {
    _shuffleState = _shuffleState.copyWith(config: config);
    shuffleStateNotifier.value = _shuffleState;
    shuffleNotifier.value = config.enabled;
    _invalidateShuffleCache();
    _saveShuffleState();

    if (applyToCurrentQueue && _effectiveQueue.isNotEmpty) {
      if (config.enabled) {
        await shuffleUpcoming(
          createNewSnapshot: createSnapshotOnQueueApply,
        );
      } else {
        await orderUpcoming(
          createNewSnapshot: createSnapshotOnQueueApply,
        );
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

    if (forceLinear && _shuffleState.config.enabled) {
      _shuffleState = _shuffleState.copyWith(
        config: _shuffleState.config.copyWith(enabled: false),
      );
      shuffleStateNotifier.value = _shuffleState;
      shuffleNotifier.value = false;
      await _saveShuffleState();
    }

    _pendingQueueSongs = null;
    _pendingQueuePlaylistId = null;
    pendingQueueNotifier.value = false;

    final currentSong = currentSongNotifier.value;
    if (currentSong != null && currentSong.filename == song.filename) {
      await _player.seek(Duration.zero);
      if (startPlaying) await _player.play();
      _savePlaybackState();
      return;
    }

    bool usedContextQueue = false;
    if (_originalQueue.isEmpty) {
      if (contextQueue != null) {
        _originalQueue = contextQueue.map((s) => QueueItem(song: s)).toList();
        _isRestrictedToOriginal = true;
        usedContextQueue = true;
      } else {
        _originalQueue = [QueueItem(song: song)];
        _isRestrictedToOriginal = false;
      }

      final originalIdx = _originalQueue.indexWhere(
        (item) => item.song.filename == song.filename,
      );

      if (_shuffleState.config.enabled && !forceLinear) {
        final otherItems = List<QueueItem>.from(_originalQueue)
          ..removeAt(originalIdx);
        final shuffledOthers = await _weightedShuffle(
          otherItems,
          lastItem: _originalQueue[originalIdx],
        );
        _effectiveQueue = [_originalQueue[originalIdx], ...shuffledOthers];
        _updateQueueNotifier();
        await _rebuildQueue(initialIndex: 0, startPlaying: startPlaying);
      } else {
        _effectiveQueue = List.from(_originalQueue);
        _updateQueueNotifier();
        await _rebuildQueue(
          initialIndex: originalIdx,
          startPlaying: startPlaying,
        );
      }

      if (usedContextQueue) {
        await _saveQueueSnapshot(contextQueue!, playlistId: playlistId);
      }

      _savePlaybackState();
      return;
    }

    final currentIndex = _player.currentIndex ?? 0;
    final targetIndex = (currentIndex + 1).clamp(0, _effectiveQueue.length);

    final duplicate = QueueItem(song: song);
    _effectiveQueue.insert(targetIndex, duplicate);

    final origTarget = (currentIndex + 1).clamp(0, _originalQueue.length);
    _originalQueue.insert(origTarget, QueueItem(song: song));

    _updateQueueNotifier();
    final insertWatch = Stopwatch()..start();
    try {
      final source = await _createAudioSource(duplicate, awaitCover: true);
      await _player.insertAudioSource(targetIndex, source);
    } catch (e) {
      _effectiveQueue.removeAt(targetIndex);
      rethrow;
    }
    _logSlow('playSong: insert source', insertWatch);

    if (startPlaying) {
      await _player.seek(Duration.zero, index: targetIndex);
      await _player.play();
    }

    _syncCoverWarmer(targetIndex);
    await _updateCurrentSnapshotSongs();
    _savePlaybackState();
  }

  StreamSubscription<T> _track<T>(StreamSubscription<T> sub) {
    _trackedSubscriptions.add(sub);
    return sub;
  }

  void _initStatsListeners() {
    // Track previous playing state for manual pause detection
    bool wasPlaying = false;

    _track(_player.playerStateStream.listen((state) {
      // Confirm fade-pause completion before checking for manual intervention
      if (_isPausingByFade && !state.playing) {
        _isPausingByFade = false;
      }

      // Detect manual pause (user pressed pause button)
      // Don't cancel transitions if we are in a gap (expected pause) or completing a fade
      if (wasPlaying &&
          !state.playing &&
          !_isInGap &&
          !_pausedByGap &&
          !_isPausingByFade) {
        _handleManualIntervention();
      }

      // Handle user pressing play during gap - cancel the gap timer
      if (_isInGap && state.playing) {
        _cancelGap();
      }

      // Reset pausedByGap after the state settles, but only outside a gap
      if (!wasPlaying && !state.playing && !_isInGap) {
        _pausedByGap = false;
      }

      wasPlaying = state.playing;

      // Keep playingNotifier in sync with actual player state
      // (unless a fade is in progress, in which case it was already set)
      if (!_isPlayPauseFading) {
        playingNotifier.value = state.playing;
      }

      if (state.playing) {
        _playStartTime ??= DateTime.now();
      } else if (_playStartTime != null) {
        _updateDurations();
        _playStartTime = null;
        _flushStats();
      }
      if (state.processingState == ProcessingState.completed) {
        _isCompleting = true;
        _flushStats(isTerminal: true);
      }
    }));

    // Listen for seek operations to cancel fade out. The fade-related seek
    // detection lives in _initFadingListeners, which owns the single
    // positionStream subscription for this player.

    _track(_player.sequenceStateStream.listen((state) {
      _syncEffectiveQueueWithPlayerSequence(state);
      final currentItem = state.currentSource?.tag;

      // Pre-fetch logic: only extend queue in radio mode (no active loop)
      final currentIndex = state.currentIndex;
      if (currentIndex != null && _effectiveQueue.isNotEmpty) {
        if (currentIndex >= _effectiveQueue.length - 2) {
          if (_shuffleState.config.enabled &&
              _player.loopMode == LoopMode.off) {
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
              _flushStats(isTerminal: true);
            }
          }
        }

        if (_currentSongFilename != newFilename) {
          final liveStartSec =
              max(0.0, _player.position.inMilliseconds / 1000.0);
          double songStartSec = liveStartSec;
          if (_pendingResumedSongStartSec != null &&
              _isResumedFromPreviousSession &&
              _previousSessionSongFilename == newFilename) {
            songStartSec = max(songStartSec, _pendingResumedSongStartSec!);
            _pendingResumedSongStartSec = null;
          }
          if (!_sessionFirstSongCaptured) {
            _sessionFirstSongCaptured = true;
            _sessionFirstSongFilename = newFilename;
            _sessionFirstSongStartSec = songStartSec;
          }

          _isCompleting = false;
          _currentSongFilename = newFilename;
          _foregroundDuration = 0.0;
          _backgroundDuration = 0.0;
          _playStartTime = _player.playing ? DateTime.now() : null;
          final song = _songMap[newFilename];
          currentSongNotifier.value = song;
          _updateEffectivePlaybackMode(song);
          _isResumedFromPreviousSession = false;
          _savePlaybackState();

          if (state.currentIndex != null) {
            _warmThemePalettesAroundIndex(state.currentIndex!);
            _syncCoverWarmer(state.currentIndex!);
          }

          // Extract color from cover
          if (song != null && _ref != null) {
            final filenameAtExtraction = newFilename;
            ColorExtractionService.extractPalette(
              song.coverUrl,
              useIsolate: true,
            ).then((palette) {
              if (palette != null &&
                  _currentSongFilename == filenameAtExtraction) {
                final processedPalette =
                    palette.withDelightned().withAlpha(200);
                _ref!
                    .read(themeProvider.notifier)
                    .updateExtractedPalette(processedPalette);
              }
            });
            _preExtractNextColor();
          }
        }
      }
    }));
  }

  // ==================== FADE AND GAP LOGIC ====================

  void _initFadingListeners() {
    _positionSubscription = _player.positionStream.listen((position) {
      if (_ref == null) return;
      // Use the cached settings populated by the settingsProvider listener
      // (set up in _initVolumeMonitoring). positionStream fires many times
      // per second, so avoid a Riverpod lookup per tick.
      final settings = _cachedSettings;
      if (settings == null) return;

      final totalDuration = _player.duration;
      if (totalDuration == null) return;

      // Minimum 30 second song for any transitions
      if (totalDuration.inSeconds < 30) return;

      final remaining = totalDuration - position;

      // Handle gap mode - pause before end, resume after delay
      if (settings.delayDuration > 0 &&
          !_isInGap &&
          _player.playing &&
          _gapTimer == null) {
        _handleGapTrigger(
          remaining: remaining,
          delayDuration: settings.delayDuration,
        );
      }

      // Handle fade out trigger
      if (settings.fadeOutDuration > 0 &&
          _player.playing &&
          !_isFadingOut &&
          remaining.inMilliseconds <= settings.fadeOutDuration * 1000 &&
          remaining.inMilliseconds > 0) {
        _startFadeOut(settings.fadeOutDuration);
      }

      // Reset fade if user seeks back. The +500 ms hysteresis matches the
      // original duplicate listener that lived in _initStatsListeners.
      if (_isFadingOut) {
        final fadeOutMs = settings.fadeOutDuration * 1000;
        if (fadeOutMs > 0 && remaining.inMilliseconds > fadeOutMs + 500) {
          _cancelTransitions();
        }
      }
    });

    _sequenceSubscription =
        _track(_player.sequenceStateStream.listen((state) async {
      if (_ref == null) return;
      // Use cached settings to avoid Riverpod lookups on every sequence
      // update (fires on every track change, but in a tighter loop during
      // gap-driven replays).
      final settings = _cachedSettings;
      if (settings == null) return;

      final currentItem = state.currentSource?.tag;
      if (currentItem is MediaItem) {
        final newFilename = currentItem.id;
        if (_lastFadedFilename != newFilename) {
          _lastFadedFilename = newFilename;
          // Reset gap state on new song
          _isInGap = false;
          _gapTimer?.cancel();
          _isFadingOut = false;
          _holdMutedUntilNextTrack = false;

          // Always reset volume on song change
          _setVolumeWithSafety(1.0);

          // Handle fade in for new song
          if (settings.fadeInDuration > 0) {
            _startFadeIn(settings.fadeInDuration);
          }
        }
      }
    }));

    // Handle completion - apply pending queue if exists, reset volume
    _track(_player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (!_holdMutedUntilNextTrack) {
          _setVolumeWithSafety(1.0);
        }
        _isFadingOut = false;

        // Apply pending queue replacement when queue completes
        if (_pendingQueueSongs != null) {
          final pendingSongs = _pendingQueueSongs!;
          final pendingPlaylistId = _pendingQueuePlaylistId;
          _pendingQueueSongs = null;
          _pendingQueuePlaylistId = null;
          pendingQueueNotifier.value = false;
          replaceQueue(pendingSongs,
              playlistId: pendingPlaylistId,
              forceLinear: true,
              clearCurrentSong: true);
        }
      }
    }));
  }

  void _generateOfflineNext() async {
    if (_isGeneratingNext) return;
    if (_player.loopMode != LoopMode.off) return;
    if (_allSongs.isEmpty) return;

    _isGeneratingNext = true;
    try {
      final currentIndex = _player.currentIndex ?? -1;
      if (currentIndex < 0) return;

      final currentItem = _effectiveQueue[currentIndex];
      final existingIds = _effectiveQueue.map((e) => e.song.filename).toSet();

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
    } finally {
      _isGeneratingNext = false;
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
        _cachedSettings = next;
        if (previous?.autoPauseOnVolumeZero != next.autoPauseOnVolumeZero) {
          _volumeMonitorService
              ?.setAutoPauseEnabled(next.autoPauseOnVolumeZero);
        }
      });

      final initialSettings = _ref!.read(settingsProvider);
      _cachedSettings = initialSettings;
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

    final sequenceState = _player.sequenceState;
    final currentItem = sequenceState.currentSource?.tag;
    if (currentItem is! MediaItem) return;

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
    _gapTimer = null;
    _wasPausedByMute = false;

    // Verify we're still on the same song
    final sequenceState = _player.sequenceState;
    final currentItem = sequenceState.currentSource?.tag;
    if (currentItem is! MediaItem || currentItem.id != expectedSongId) {
      // User skipped/changed song during gap
      return;
    }

    // Skip to next song after gap and resume playback
    if (_player.hasNext) {
      _player.seekToNext();
    }
    _player.play();
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

  void _startFadeOut(double duration) {
    _fadeTimer?.cancel();
    _isFadingOut = true;
    _holdMutedUntilNextTrack = false;
    _fadeDurationMs = duration * 1000;
    _fadeStartTime = DateTime.now();

    _fadeTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_fadeStartTime == null || _fadeDurationMs == null) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_fadeStartTime!).inMilliseconds;
      final targetMs = _fadeDurationMs!;

      if (elapsed >= targetMs) {
        _setVolumeWithSafety(0.01);
        _isFadingOut = false;
        _holdMutedUntilNextTrack = true;
        _fadeStartTime = null;
        _fadeDurationMs = null;
        timer.cancel();
      } else {
        final linearProgress = 1.0 - (elapsed / targetMs);
        final curvedVolume = _fadeOutCurve(linearProgress.clamp(0.0, 1.0));
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

  /// Toggles playback with optional fade based on settings.
  void togglePlayPause() {
    if (_player.playing) {
      fadeAndPause();
    } else {
      fadeAndPlay();
    }
  }

  /// Fades volume to 0 over pauseFadeDuration, then pauses and restores volume.
  void fadeAndPause() {
    if (!_player.playing) return;
    _playPauseFadeTimer?.cancel();

    final settings = _ref?.read(settingsProvider);
    final fadeDurationMs =
        ((settings?.pauseFadeDuration ?? 0.0) * 1000).toInt();

    if (fadeDurationMs <= 0) {
      _isPausingByFade = true;
      _player.pause();
      return;
    }
    playingNotifier.value = false;
    _isPlayPauseFading = true;
    final startTime = DateTime.now();
    final startVolume = _targetVolume;

    _playPauseFadeTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed >= fadeDurationMs || !_player.playing) {
        timer.cancel();
        _isPlayPauseFading = false;
        _isPausingByFade = true;
        _setVolumeWithSafety(0.01);
        _player.pause();
        _setVolumeWithSafety(1.0);
        return;
      }
      final progress = elapsed / fadeDurationMs;
      final curved = startVolume * (1.0 - pow(progress, 0.5));
      _setVolumeWithSafety(curved.toDouble());
    });
  }

  /// Starts playback at volume 0 then fades up over playFadeDuration.
  void fadeAndPlay() {
    _playPauseFadeTimer?.cancel();
    _wasPausedByMute = false;

    final settings = _ref?.read(settingsProvider);
    final fadeDurationMs = ((settings?.playFadeDuration ?? 0.0) * 1000).toInt();

    if (fadeDurationMs <= 0) {
      _player.play();
      return;
    }

    // Show playing state in UI immediately, before the fade starts
    playingNotifier.value = true;
    _setVolumeWithSafety(0.0);
    _player.play();
    _isPlayPauseFading = true;
    final startTime = DateTime.now();

    _playPauseFadeTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed >= fadeDurationMs) {
        timer.cancel();
        _isPlayPauseFading = false;
        _setVolumeWithSafety(1.0);
        return;
      }
      final progress = elapsed / fadeDurationMs;
      final curved = pow(progress, 0.5).toDouble();
      _setVolumeWithSafety(curved);
    });
  }

  void _resetFading() {
    _fadeTimer?.cancel();
    _playPauseFadeTimer?.cancel();
    _isFadingOut = false;
    _holdMutedUntilNextTrack = false;
    _isPlayPauseFading = false;
    _isPausingByFade = false;
    _fadeStartTime = null;
    _fadeDurationMs = null;
    _targetVolume = 1.0;
    _setVolumeWithSafety(1.0);
  }

  void _cancelTransitions() {
    _cancelGap();
    _fadeTimer?.cancel();
    _playPauseFadeTimer?.cancel();
    _isFadingOut = false;
    _holdMutedUntilNextTrack = false;
    _isPlayPauseFading = false;
    _isPausingByFade = false;
    _fadeStartTime = null;
    _fadeDurationMs = null;
    _targetVolume = 1.0;
    _setVolumeWithSafety(1.0);
  }

  void _cancelGap() {
    _isInGap = false;
    _pausedByGap = false;
    _gapTimer?.cancel();
    _clearGapState();
  }

  void _handleManualIntervention() {
    // User manually paused - cancel any ongoing transitions
    _cancelTransitions();
  }

  // ==================== GAP STATE PERSISTENCE ====================

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
      final sequenceState = _player.sequenceState;
      final currentItem = sequenceState.currentSource?.tag;
      if (currentItem is! MediaItem || currentItem.id != songId) {
        await _clearGapState();
        return;
      }

      // Restore gap state
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

  void _setCacheLimits({required bool isBackground}) {
    if (isBackground) {
      PaintingBinding.instance.imageCache.maximumSize = _backgroundCacheSize;
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          _backgroundCacheBytes;
    } else {
      PaintingBinding.instance.imageCache.maximumSize = _foregroundCacheSize;
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          _foregroundCacheBytes;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_playStartTime != null) {
      _updateDurations();
      _playStartTime = DateTime.now();
    }

    final isBackground = state != AppLifecycleState.resumed;
    NotificationCoverWarmer.instance.setForeground(!isBackground);

    if (isBackground) {
      _flushStats(isTerminal: true);
      savePlaybackState();
      _setCacheLimits(isBackground: true);
      _statsService.flush();
    } else {
      _setCacheLimits(isBackground: false);
    }

    _statsService.setBackground(isBackground);

    _appLifecycleState = state;
  }

  void onMemoryPressure() {
    // Lower the LRU caps so Flutter trims aggressively on its own; this
    // avoids the wholesale clear() that would force regen of expensive
    // blurred backgrounds.
    PaintingBinding.instance.imageCache.maximumSize = 20;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 5 * 1024 * 1024;
  }

  // ==================== STATS & SHUFFLE ====================

  void _preExtractNextColor() {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null || _effectiveQueue.isEmpty) return;

    final nextIndex = currentIndex + 1;
    if (nextIndex >= _effectiveQueue.length) return;

    final nextSong = _effectiveQueue[nextIndex].song;
    if (nextSong.coverUrl != null) {
      ColorExtractionService.extractPalette(
        nextSong.coverUrl,
        useIsolate: true,
      );
    }
  }

  void _warmThemePalette(String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) return;
    unawaited(
      ColorExtractionService.extractPalette(
        coverUrl,
        useIsolate: true,
      ),
    );
  }

  void _warmThemePalettesAroundIndex(int centerIndex, {int radius = 1}) {
    if (_effectiveQueue.isEmpty) return;

    for (int offset = -radius; offset <= radius; offset++) {
      final index = centerIndex + offset;
      if (index < 0 || index >= _effectiveQueue.length) continue;
      _warmThemePalette(_effectiveQueue[index].song.coverUrl);
    }
  }

  Future<ShuffleState?> syncShuffleState() async {
    return _shuffleState;
  }

  Future<void> _saveShuffleState() async {
    await _storageService.saveShuffleState(_shuffleState.toJson());
  }

  /// Queues a playback-state write, coalescing bursts.
  ///
  /// The state embeds both full queues, so encoding it is proportional to the
  /// library size — and startup alone triggers it from a dozen call sites.
  /// Callers that need the write to have landed use [savePlaybackState].
  void _savePlaybackState() {
    if (_playbackStateSaveTimer?.isActive ?? false) return;
    _playbackStateSaveTimer = Timer(_playbackStateSaveInterval, () {
      unawaited(_writePlaybackState());
    });
  }

  Future<void> _writePlaybackState() async {
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
      'current_queue_snapshot_id': _currentQueueSnapshotId,
      'preferred_media_mode': preferredMediaModeNotifier.value.name,
    };

    await _storageService.savePlaybackState(state);
  }

  /// Writes the playback state immediately, cancelling any coalesced write.
  Future<void> savePlaybackState() async {
    _playbackStateSaveTimer?.cancel();
    await _writePlaybackState();
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

  void _flushStats({bool isTerminal = false}) {
    if (_currentSongFilename == null) return;
    if (_playStartTime != null) _updateDurations();

    final song = _songMap[_currentSongFilename!];
    final totalLength =
        (song?.duration?.inMilliseconds.toDouble() ?? 0.0) / 1000.0;
    double effectiveTotalLength = totalLength;
    final firstSongStartSec = _sessionFirstSongStartSec;
    final isFirstSongMidStart =
        _currentSongFilename == _sessionFirstSongFilename &&
            firstSongStartSec != null &&
            firstSongStartSec > 0;
    if (isFirstSongMidStart && totalLength > 0) {
      final adjustedLength = max(0.0, totalLength - firstSongStartSec);
      if (adjustedLength > 0) {
        effectiveTotalLength = adjustedLength;
      }
    }

    double finalDuration = _foregroundDuration + _backgroundDuration;

    if (finalDuration > 0.5) {
      unawaited(_statsService.trackStats({
        'song_filename': _currentSongFilename!,
        'duration_played': finalDuration,
        'foreground_duration': _foregroundDuration,
        'background_duration': _backgroundDuration,
        'total_length': effectiveTotalLength,
      }));
    }
    _foregroundDuration = 0.0;
    _backgroundDuration = 0.0;
    if (isTerminal) {
      _playStartTime = null;
    } else if (_playStartTime != null) {
      _playStartTime = DateTime.now();
    }
    unawaited(_statsService.flush());
    _ref?.read(songsProvider.notifier).refreshPlayCounts();
  }

  // ==================== INIT & QUEUE ====================

  static List<QueueItem> _parseQueueItems(List<dynamic> json) {
    final items = <QueueItem>[];
    for (final entry in json) {
      try {
        items.add(QueueItem.fromJson(entry));
      } catch (_) {
        // A single unreadable entry must not cost us the whole saved queue.
      }
    }
    return items;
  }

  /// The subset of [paths] that no longer exist on disk, resolved off the UI
  /// thread.
  static Future<Set<String>> _findMissingSongPaths(Set<String> paths) async {
    final candidates = paths.where((path) => path.isNotEmpty).toList();
    if (candidates.isEmpty) return const <String>{};
    try {
      return await Isolate.run(() => {
            for (final path in candidates)
              if (!File(path).existsSync()) path,
          });
    } catch (e) {
      // If the isolate cannot run, keep every entry rather than wrongly
      // dropping the user's whole queue.
      debugPrint('AudioPlayerManager: queue existence check failed: $e');
      return const <String>{};
    }
  }

  Future<void> init(List<Song> songs, {bool autoSelect = false}) async {
    _allSongs = songs;
    _songMap = {for (var s in songs) s.filename: s};
    _isRestrictedToOriginal = false;
    await _player.setShuffleModeEnabled(false);

    await DatabaseService.instance.init();

    final savedState = await _storageService.loadPlaybackState();

    if (savedState != null) {
      try {
        final savedPreferredMode =
            savedState['preferred_media_mode'] as String?;
        preferredMediaModeNotifier.value = savedPreferredMode == 'video'
            ? PlaybackMediaMode.video
            : PlaybackMediaMode.audio;

        final List<dynamic> effJson = savedState['last_effective_queue'] ?? [];
        final List<dynamic> origJson = savedState['last_original_queue'] ?? [];

        final restoreWatch = Stopwatch()..start();
        final effItems = _parseQueueItems(effJson);
        final origItems = _parseQueueItems(origJson);

        // Both queues are the whole library on a cold start, so checking each
        // file inline would be hundreds of blocking stat calls on the UI
        // thread. One isolate covers both lists at once.
        final missing = await _findMissingSongPaths({
          for (final item in effItems) item.song.url,
          for (final item in origItems) item.song.url,
        });
        bool exists(QueueItem item) =>
            item.song.url.isNotEmpty && !missing.contains(item.song.url);

        _effectiveQueue = effItems.where(exists).toList();
        _originalQueue = origItems.where(exists).toList();
        _logSlow('init: restored saved queue', restoreWatch);

        if (_effectiveQueue.isNotEmpty || _originalQueue.isNotEmpty) {
          _isRestrictedToOriginal =
              savedState['is_restricted_to_original'] ?? false;
          _currentPlaylistId = savedState['current_playlist_id'];
          _currentQueueSnapshotId = savedState['current_queue_snapshot_id'];

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
              _pendingResumedSongStartSec =
                  max(0.0, resumePosition.inMilliseconds / 1000.0);
            } else {
              initialIndex = 0;
            }
          }

          await _rebuildQueue(
            initialIndex: initialIndex,
            startPlaying: false,
            initialPosition: resumePosition,
          );
          _updateEffectivePlaybackMode();
          return;
        }
      } catch (e) {
        // Ignore
      }
    }

    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _effectiveQueue = List.from(_originalQueue);

    int initialIndex = 0;
    Duration? resumePosition;

    if (savedState != null) {
      final lastSongFilename = savedState['last_song_filename'] as String?;
      final savedPositionMs = savedState['last_position_ms'] as int?;
      if (lastSongFilename != null && savedPositionMs != null) {
        final songIndex =
            songs.indexWhere((s) => s.filename == lastSongFilename);
        if (songIndex != -1) {
          initialIndex = songIndex;
          resumePosition = Duration(milliseconds: savedPositionMs);
          _previousSessionSongFilename = lastSongFilename;
          _isResumedFromPreviousSession = true;
          _pendingResumedSongStartSec =
              max(0.0, resumePosition.inMilliseconds / 1000.0);
        }
      }
    }

    if (autoSelect && songs.isNotEmpty && resumePosition == null) {
      initialIndex = Random().nextInt(songs.length);
    }
    await _rebuildQueue(
        initialIndex: initialIndex,
        startPlaying: false,
        initialPosition: resumePosition);
    _updateEffectivePlaybackMode();
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
    _updateEffectivePlaybackMode();

    if (currentIdx != null && currentItemBefore != null) {
      final currentItemAfter = _effectiveQueue[currentIdx];
      if (currentItemBefore.song.url != currentItemAfter.song.url ||
          currentItemBefore.song.filename != currentItemAfter.song.filename) {
        _rebuildQueue(initialIndex: currentIdx, startPlaying: _player.playing);
      }
    }
  }

  /// Builds the player entry for [item].
  ///
  /// [awaitCover] is for the one song the user is starting: it blocks on
  /// producing the square notification cover so the notification is right
  /// immediately. Every other entry takes the synchronous path — an already
  /// cached cover if there is one, otherwise the raw art, with the square
  /// version left to [NotificationCoverWarmer]. Awaiting it for a whole queue
  /// is what used to stall a cold start for the best part of a minute.
  Future<AudioSource> _createAudioSource(
    QueueItem item, {
    bool awaitCover = false,
  }) async {
    final song = item.song;
    final mediaPaths = await _resolvePlayableMediaPaths(song);
    final Uri audioUri = Uri.file(mediaPaths.audioPath);

    Uri? artUri;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final coverSizingMode = _ref?.read(settingsProvider).coverSizingMode ??
          PlayerCoverSizingMode.sourceAspect;
      String? coverPath;
      if (awaitCover) {
        final fileManager = _ref?.read(fileManagerServiceProvider);
        coverPath = fileManager == null
            ? song.coverUrl
            : await fileManager.getOrCreateNotificationCover(
                song,
                coverSizingMode,
              );
      } else {
        coverPath =
            FileManagerService.peekNotificationCover(song, coverSizingMode) ??
                song.coverUrl;
      }
      if (coverPath != null) {
        artUri = Uri.file(coverPath);
      }
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
          'hasVideo': song.hasVideo,
          'remoteUrl': song.url,
          'queueId': item.queueId,
          'androidStopForegroundOnPause': !keepNotification,
          'audioPath': song.url,
          'playbackAudioPath': mediaPaths.audioPath,
          if (mediaPaths.videoPath != null) 'videoPath': mediaPaths.videoPath,
        },
      ),
    );
  }

  Future<({String audioPath, String? videoPath})> _resolvePlayableMediaPaths(
    Song song,
  ) async {
    if (!Platform.isIOS) {
      return (audioPath: song.url, videoPath: song.hasVideo ? song.url : null);
    }

    final ffmpeg = FFmpegService();
    final needsAudioProxy = !_isIosNativeAudioPath(song.url);
    final audioPath = needsAudioProxy
        ? (await ffmpeg.prepareIosAudioProxy(song.url)) ?? song.url
        : song.url;

    String? videoPath = song.hasVideo ? song.url : null;
    if (song.hasVideo && !_isIosNativeVideoPath(song.url)) {
      videoPath = await ffmpeg.prepareIosVideoProxy(song.url) ?? song.url;
    }

    return (audioPath: audioPath, videoPath: videoPath);
  }

  bool _isIosNativeAudioPath(String path) {
    const supported = {
      '.aac',
      '.aif',
      '.aiff',
      '.caf',
      '.flac',
      '.m4a',
      '.m4b',
      '.mp3',
      '.mp4',
      '.m4v',
      '.mov',
      '.wav',
    };
    return supported.contains(p.extension(path).toLowerCase());
  }

  bool _isIosNativeVideoPath(String path) {
    const supported = {
      '.3gp',
      '.m4v',
      '.mov',
      '.mp4',
    };
    return supported.contains(p.extension(path).toLowerCase());
  }

  void _updateQueueNotifier() {
    final next = List<QueueItem>.from(_effectiveQueue);
    // Skip the new-list allocation and listener notification when the
    // queue contents are identical. queueNotifier listeners rebuild
    // large UI sections, so the comparison is well worth the O(N) walk.
    final current = queueNotifier.value;
    if (_listEqualsQueue(current, next)) {
      return;
    }
    queueNotifier.value = next;
  }

  static bool _listEqualsQueue(List<QueueItem> a, List<QueueItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].song.filename != b[i].song.filename) return false;
    }
    return true;
  }

  /// Runs [body] with the sequence-sync listener suppressed, so our own
  /// intermediate player states can never be mistaken for an outside edit.
  Future<T> _guardPlayerMutation<T>(Future<T> Function() body) async {
    _playerMutationDepth++;
    try {
      return await body();
    } finally {
      _playerMutationDepth--;
      if (_playerMutationDepth == 0) {
        // Publish the authoritative model once the whole mutation has landed.
        _updateQueueNotifier();
      }
    }
  }

  Future<T> _runSerializedQueueMutation<T>(
    Future<T> Function() mutation,
  ) {
    final next =
        _queueMutationChain.then((_) => _guardPlayerMutation(mutation));
    _queueMutationChain = next.then<void>(
      (_) {},
      onError: (e, _) {
        debugPrint('Queue mutation failed: $e');
      },
    );
    return next;
  }

  bool _sameQueueSnapshot(List<QueueItem> first, List<QueueItem> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  void _syncEffectiveQueueWithPlayerSequence(SequenceState state) {
    // Our own mutations rewrite the player's sources step by step; adopting an
    // intermediate sequence here would truncate the queue mid-edit.
    if (_playerMutationDepth > 0) return;

    final sequence = state.sequence;
    if (sequence.isEmpty) return;

    final entries = <queue_ops.SequenceEntry>[];
    for (final source in sequence) {
      final tag = source.tag;
      if (tag is! MediaItem) continue;
      entries.add((
        filename: tag.id,
        queueId: tag.extras?['queueId'] as String?,
      ));
    }

    final rebuilt = queue_ops.reconcileWithSequence(
      _effectiveQueue,
      entries,
      (filename) {
        final song = _songMap[filename];
        return song == null ? null : QueueItem(song: song);
      },
    );

    if (rebuilt.isEmpty || _sameQueueSnapshot(_effectiveQueue, rebuilt)) return;
    _effectiveQueue = rebuilt;
    _updateQueueNotifier();
    _savePlaybackState();
  }

  Future<void> shuffleAndPlay(
    List<Song> songs, {
    bool isRestricted = false,
  }) async {
    if (songs.isEmpty) return;

    _resetFading();
    await _player.setShuffleModeEnabled(false);

    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: true),
    );
    shuffleNotifier.value = true;
    shuffleStateNotifier.value = _shuffleState;
    _saveShuffleState();

    // Clear any pending queue replacement
    _pendingQueueSongs = null;
    _pendingQueuePlaylistId = null;
    pendingQueueNotifier.value = false;

    // Set up fresh queue (always replaces current queue entirely)
    _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
    _isRestrictedToOriginal = isRestricted;
    _currentPlaylistId = null;

    final randomIdx = Random().nextInt(songs.length);
    final selectedItem = _originalQueue[randomIdx];

    // Build shuffled effective queue for the selected song
    final otherItems = List<QueueItem>.from(_originalQueue)
      ..removeAt(randomIdx);
    final shuffledOthers = await _weightedShuffle(
      otherItems,
      lastItem: selectedItem,
    );
    _effectiveQueue = [selectedItem, ...shuffledOthers];
    _updateQueueNotifier();

    // Replace player queue and start playing
    await _rebuildQueue(initialIndex: 0, startPlaying: true);

    // Save snapshot for non-folder shuffles
    if (!isRestricted) {
      await _saveQueueSnapshot(songs, playlistId: null);
    }

    _savePlaybackState();
  }

  Future<void> toggleShuffle() async {
    final isShuffle = !shuffleNotifier.value;
    shuffleNotifier.value = isShuffle;
    _shuffleState = _shuffleState.copyWith(
      config: _shuffleState.config.copyWith(enabled: isShuffle),
    );
    shuffleStateNotifier.value = _shuffleState;
    await updateShuffleConfig(
      _shuffleState.config,
      createSnapshotOnQueueApply: isShuffle,
    );
  }

  Future<void> replaceQueue(
    List<Song> songs, {
    String? playlistId,
    bool forceLinear = false,
    bool saveSnapshot = true,
    bool clearCurrentSong = false,
  }) async {
    if (songs.isEmpty) return;

    // Clear any pending queue replacement since we're replacing immediately
    _pendingQueueSongs = null;
    _pendingQueuePlaylistId = null;
    pendingQueueNotifier.value = false;

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

      if (!clearCurrentSong && currentSong != null && isPlaying) {
        final currentItem = QueueItem(song: currentSong);
        _effectiveQueue = [currentItem, ..._originalQueue];
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      } else {
        _effectiveQueue = List.from(_originalQueue);
        await _rebuildQueue(initialIndex: 0, startPlaying: true);
      }
    } else {
      _resetFading();
      await _player.setShuffleModeEnabled(false);
      _originalQueue = songs.map((s) => QueueItem(song: s)).toList();
      _isRestrictedToOriginal = true;

      if (_shuffleState.config.enabled) {
        final firstItem = _originalQueue.first;
        final otherItems = List<QueueItem>.from(_originalQueue)..removeAt(0);
        final shuffledOthers = await _weightedShuffle(
          otherItems,
          lastItem: firstItem,
        );
        _effectiveQueue = [firstItem, ...shuffledOthers];
      } else {
        _effectiveQueue = List.from(_originalQueue);
      }

      if (!clearCurrentSong && currentSong != null && isPlaying) {
        final currentItem = QueueItem(song: currentSong);
        _effectiveQueue = [currentItem, ..._effectiveQueue];
      }
      await _rebuildQueue(initialIndex: 0, startPlaying: true);
    }

    if (saveSnapshot) {
      await _saveQueueSnapshot(songs, playlistId: playlistId);
    }

    _savePlaybackState();
    _updateQueueNotifier();
  }

  Future<void> _saveQueueSnapshot(List<Song> songs,
      {String? playlistId}) async {
    if (songs.isEmpty) return;

    final watch = Stopwatch()..start();
    final songFilenames = songs.map((s) => s.filename).toList();
    final source = playlistId ?? 'shuffle';
    final existing = await _findExistingQueueSnapshot(source, songFilenames);
    _logSlow('saveQueueSnapshot: dedupe scan', watch);
    if (existing != null) {
      _currentQueueSnapshotId = existing.id;
      _savePlaybackState();
      return;
    }

    final snapshot = QueueSnapshot.create(
      songFilenames: songFilenames,
      source: source,
    );
    _currentQueueSnapshotId = snapshot.id;
    try {
      await DatabaseService.instance.saveQueueSnapshot(
        snapshot.id,
        snapshot.name,
        snapshot.createdAt,
        snapshot.source,
        snapshot.songFilenames,
      );
      // Trim the queue history so it doesn't grow unbounded across long
      // sessions. Runs only on fresh insertions.
      unawaited(DatabaseService.instance.pruneQueueSnapshots());
      _notifyQueueHistoryChanged();
      _savePlaybackState();
    } catch (e) {
      debugPrint('Failed to save queue snapshot: $e');
    }
  }

  Future<QueueSnapshot?> _findExistingQueueSnapshot(
    String source,
    List<String> songFilenames,
  ) async {
    try {
      final snapshots =
          await DatabaseService.instance.getQueueHistorySnapshots();
      for (final snapshot in snapshots) {
        if (snapshot.source != source) continue;
        if (_sameFilenameList(snapshot.songFilenames, songFilenames)) {
          return snapshot;
        }
      }
    } catch (e) {
      debugPrint('Failed to check queue snapshot duplicates: $e');
    }
    return null;
  }

  bool _sameFilenameList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  Future<void> _updateCurrentSnapshotSongs() async {
    var id = _currentQueueSnapshotId;
    if (id == null) {
      if (_effectiveQueue.isEmpty) return;
      await _saveQueueSnapshot(
        _effectiveQueue.map((item) => item.song).toList(),
        playlistId: _currentPlaylistId,
      );
      id = _currentQueueSnapshotId;
      if (id == null) return;
    }

    final filenames = _effectiveQueue.map((q) => q.song.filename).toList();
    try {
      await DatabaseService.instance.updateQueueSnapshotSongs(id, filenames);
      _notifyQueueHistoryChanged();
    } catch (e) {
      debugPrint('Failed to update queue snapshot: $e');
    }
  }

  void _notifyQueueHistoryChanged() {
    final ref = _ref;
    if (ref == null || !ref.mounted) return;
    ref.invalidate(queueHistoryProvider);
  }

  void setPendingQueueReplacement(List<Song> songs, {String? playlistId}) {
    _pendingQueueSongs = songs;
    _pendingQueuePlaylistId = playlistId;
    pendingQueueNotifier.value = true;
  }

  void cancelPendingQueueReplacement() {
    _pendingQueueSongs = null;
    _pendingQueuePlaylistId = null;
    pendingQueueNotifier.value = false;
  }

  /// Reorders only the tracks after the current one.
  ///
  /// The current track and everything already played stay exactly where they
  /// are, and the set of queued songs is never touched — this is purely a
  /// reordering, so flipping shuffle can never add or drop tracks. Because only
  /// sources after the current index are rewritten, the track that is playing
  /// is never re-created and audio does not stutter.
  Future<void> _reorderUpcoming(
    Future<List<QueueItem>> Function(List<QueueItem>, QueueItem) reorder, {
    bool createNewSnapshot = false,
  }) async {
    await _runSerializedQueueMutation(() async {
      if (_effectiveQueue.isEmpty) return;

      final currentIndex =
          (_player.currentIndex ?? 0).clamp(0, _effectiveQueue.length - 1);
      final currentItem = _effectiveQueue[currentIndex];
      final upcoming = _effectiveQueue.sublist(currentIndex + 1);

      if (upcoming.length > 1) {
        final reordered = await reorder(upcoming, currentItem);
        _effectiveQueue = [
          ..._effectiveQueue.sublist(0, currentIndex + 1),
          ...reordered,
        ];
        await _mutateQueueAfterIndex(currentIndex);
        _warmThemePalettesAroundIndex(currentIndex);
      }

      if (createNewSnapshot) {
        await _saveQueueSnapshot(
          _effectiveQueue.map((item) => item.song).toList(),
          playlistId: _currentPlaylistId,
        );
      } else {
        await _updateCurrentSnapshotSongs();
      }
      _savePlaybackState();
    });
  }

  /// Shuffles everything after the current track, in place.
  Future<void> shuffleUpcoming({bool createNewSnapshot = false}) {
    return _reorderUpcoming(
      (upcoming, current) => _weightedShuffle(upcoming, lastItem: current),
      createNewSnapshot: createNewSnapshot,
    );
  }

  /// Restores original queue order for everything after the current track.
  Future<void> orderUpcoming({bool createNewSnapshot = false}) {
    return _reorderUpcoming(
      (upcoming, current) async => _inOriginalOrder(upcoming, current),
      createNewSnapshot: createNewSnapshot,
    );
  }

  /// Sorts [upcoming] back into original queue order, resuming from where
  /// [current] sits in that order and wrapping around to the start — so turning
  /// shuffle off continues the album or playlist from the right place rather
  /// than jumping back to track one.
  List<QueueItem> _inOriginalOrder(
    List<QueueItem> upcoming,
    QueueItem current,
  ) {
    final byQueueId = <String, int>{};
    final byFilename = <String, int>{};
    for (int i = 0; i < _originalQueue.length; i++) {
      byQueueId[_originalQueue[i].queueId] = i;
      byFilename.putIfAbsent(_originalQueue[i].song.filename, () => i);
    }

    // Duplicated entries carry a fresh queueId, so fall back to the filename.
    int? positionOf(QueueItem item) =>
        byQueueId[item.queueId] ?? byFilename[item.song.filename];

    final anchor = positionOf(current) ?? -1;
    final length = _originalQueue.length;

    // Entries the original queue never had — added via Play Next, or generated
    // on the fly — have no natural position, so they keep their relative order
    // at the end rather than being dropped.
    final known = <QueueItem>[];
    final unknown = <QueueItem>[];
    for (final item in upcoming) {
      (positionOf(item) == null ? unknown : known).add(item);
    }

    int rank(QueueItem item) {
      final position = positionOf(item)!;
      return position > anchor ? position : position + length;
    }

    known.sort((a, b) => rank(a).compareTo(rank(b)));
    return [...known, ...unknown];
  }

  Future<List<QueueItem>> _weightedShuffle(
    List<QueueItem> items, {
    QueueItem? lastItem,
  }) async {
    if (items.isEmpty) return [];

    final now = DateTime.now();
    final cacheValid = _shuffleCacheTimestamp != null &&
        now.difference(_shuffleCacheTimestamp!) < _shuffleCacheDuration;

    if (!cacheValid || _cachedPlayCounts == null) {
      final results = await Future.wait([
        DatabaseService.instance.getPlayCounts(),
        DatabaseService.instance.getSkipStats(),
        DatabaseService.instance
            .getPlayHistory(limit: _shuffleState.config.historyLimit),
      ]);
      _cachedPlayCounts = results[0] as Map<String, int>;
      _cachedSkipStats =
          results[1] as Map<String, ({int count, double avgRatio})>;
      _cachedPlayHistory = results[2] as List<
          ({
            String filename,
            double timestamp,
            double playRatio,
            String eventType
          })>;
      _shuffleCacheTimestamp = now;
    }

    final playCounts = _cachedPlayCounts!;
    final skipStats = _cachedSkipStats!;
    final playHistory = _cachedPlayHistory!;

    // Build O(1) lookup tables for play history. The naive implementation
    // scanned playHistory for every item on every weight iteration, leading
    // to O(N * historySize) per pass.
    final historyIndexByFilename = <String, int>{};
    final playRatioByFilename = <String, double>{};
    for (int i = 0; i < playHistory.length; i++) {
      final entry = playHistory[i];
      // First occurrence wins (smallest index), which is what the original
      // linear scan captured.
      historyIndexByFilename.putIfAbsent(entry.filename, () => i);
      playRatioByFilename.putIfAbsent(entry.filename, () => entry.playRatio);
    }

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
                item,
                prev,
                playCounts,
                skipStats,
                maxPlayCount,
                historyIndexByFilename,
                playRatioByFilename,
              ))
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
    return _filenameToGroupId[filename];
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
    Map<String, int> historyIndexByFilename,
    Map<String, double> playRatioByFilename,
  ) {
    final representative = item.representative;
    final config = _shuffleState.config;

    final bool isCustomMode = config.personality == ShufflePersonality.custom;

    // Compute merge-group aggregates, or use single-item values directly.
    int groupPlayCount;
    bool isFavorite;
    bool isSuggestLess;
    int? historyIndex;
    double? playRatioInHistory;
    int? skipCount;
    double? skipAvgRatio;

    if (item.type == _VirtualItemType.mergeGroup) {
      groupPlayCount = 0;
      isFavorite = false;
      isSuggestLess = false;
      double totalSkipRatio = 0.0;
      int skipItems = 0;

      int? bestHistoryIndex;

      for (final queueItem in item.items) {
        groupPlayCount += playCounts[queueItem.song.filename] ?? 0;

        if (_isFavorite(queueItem.song.filename)) isFavorite = true;
        if (_isSuggestLess(queueItem.song.filename)) isSuggestLess = true;

        final idx = historyIndexByFilename[queueItem.song.filename];
        if (idx != null &&
            (bestHistoryIndex == null || idx < bestHistoryIndex)) {
          bestHistoryIndex = idx;
          playRatioInHistory = playRatioByFilename[queueItem.song.filename];
        }

        if (isCustomMode) {
          final ss = skipStats[queueItem.song.filename];
          if (ss != null && ss.count > 0) {
            totalSkipRatio += ss.avgRatio;
            skipItems++;
          }
        }
      }

      historyIndex = bestHistoryIndex;

      if (isCustomMode && skipItems > 0) {
        skipCount = skipItems;
        skipAvgRatio = totalSkipRatio / skipItems;
      }
    } else {
      groupPlayCount = playCounts[representative.song.filename] ?? 0;
      isFavorite = _isFavorite(representative.song.filename);
      isSuggestLess = _isSuggestLess(representative.song.filename);
      historyIndex = historyIndexByFilename[representative.song.filename];
      playRatioInHistory = playRatioByFilename[representative.song.filename];

      if (isCustomMode) {
        final ss = skipStats[representative.song.filename];
        if (ss != null && ss.count > 0) {
          skipCount = ss.count;
          skipAvgRatio = ss.avgRatio;
        }
      }
    }

    return calculateWeight(
      item: representative,
      prev: prev?.representative,
      config: config,
      isFavorite: isFavorite,
      isSuggestLess: isSuggestLess,
      playCount: groupPlayCount,
      maxPlayCount: maxPlayCount,
      historyIndex: historyIndex,
      playRatioInHistory: playRatioInHistory,
      skipCount: skipCount,
      skipAvgRatio: skipAvgRatio,
    );
  }

  Future<void> _rebuildQueue({
    int? initialIndex,
    bool startPlaying = true,
    Duration? initialPosition,
  }) =>
      _guardPlayerMutation(() => _rebuildQueueInner(
            initialIndex: initialIndex,
            startPlaying: startPlaying,
            initialPosition: initialPosition,
          ));

  Future<void> _rebuildQueueInner({
    int? initialIndex,
    bool startPlaying = true,
    Duration? initialPosition,
  }) async {
    if (_effectiveQueue.isEmpty) return;

    final sequenceState = _player.sequenceState;
    final currentMediaItem = sequenceState.currentSource?.tag as MediaItem?;
    final requestedIndex = initialIndex ?? _player.currentIndex ?? 0;
    final targetIndex = requestedIndex.clamp(0, _effectiveQueue.length - 1);
    final currentItem =
        (targetIndex >= 0 && targetIndex < _effectiveQueue.length)
            ? _effectiveQueue[targetIndex]
            : null;

    final currentQueueId = currentMediaItem?.extras?['queueId'] as String?;
    final trackChanged = currentItem != null
        ? currentQueueId != currentItem.queueId
        : currentMediaItem != null;
    if (trackChanged) {
      _resetFading();
    }

    _warmThemePalettesAroundIndex(targetIndex);

    final currentPosition = _player.position;

    Duration position = Duration.zero;
    if (initialPosition != null) {
      position = initialPosition;
    } else if (currentMediaItem != null && currentItem != null) {
      if (currentQueueId == currentItem.queueId) {
        position = currentPosition;
      }
    }

    // One directory listing up front so every entry below can resolve its
    // cover art synchronously instead of stat-ing the cache per song.
    await FileManagerService.primeNotificationCoverIndex();

    final buildWatch = Stopwatch()..start();
    final sources = await Future.wait([
      for (int i = 0; i < _effectiveQueue.length; i++)
        _createAudioSource(_effectiveQueue[i], awaitCover: i == targetIndex),
    ]);
    _logSlow('rebuild: built ${sources.length} sources', buildWatch);

    final setWatch = Stopwatch()..start();
    await _player.setAudioSources(
      sources,
      initialIndex: targetIndex,
      initialPosition: position,
    );
    _logSlow('rebuild: setAudioSources(${sources.length})', setWatch);
    _updateEffectivePlaybackMode(currentItem?.song);

    if (startPlaying) await _player.play();
    _updateQueueNotifier();
    _syncCoverWarmer(targetIndex);
  }

  /// Hands the warmer the current queue so it works on whatever plays next
  /// first. Cheap enough to call after any queue mutation.
  void _syncCoverWarmer([int? currentIndex]) {
    final mode = _ref?.read(settingsProvider).coverSizingMode;
    if (mode == null) return;
    NotificationCoverWarmer.instance.setQueue(
      _effectiveQueue.map((item) => item.song).toList(),
      currentIndex ?? _player.currentIndex ?? 0,
      mode,
    );
  }

  /// Reports a step that took long enough for a user to feel it. Deliberately
  /// not gated on [kDebugMode] — the startup stalls this exists to catch only
  /// reproduce on real devices running release builds.
  void _logSlow(String label, Stopwatch watch) {
    watch.stop();
    if (watch.elapsedMilliseconds < 250) return;
    debugPrint(
      'AudioPlayerManager: $label took ${watch.elapsedMilliseconds}ms',
    );
  }

  Future<void> _mutateQueueAfterIndex(int currentIndex) async {
    if (currentIndex < 0) return;

    // Snapshot the intended tail before touching the player. Mid-loop the
    // player's sequence briefly shrinks to a single item; if anything else read
    // _effectiveQueue off that transient state we would rebuild from garbage,
    // so the loops are driven from this immutable copy instead.
    final tail = _effectiveQueue.length > currentIndex + 1
        ? List<QueueItem>.from(_effectiveQueue.sublist(currentIndex + 1))
        : <QueueItem>[];

    await _guardPlayerMutation(() async {
      try {
        final playerLen = _player.sequenceState.sequence.length;
        for (int i = playerLen - 1; i > currentIndex; i--) {
          await _player.removeAudioSourceAt(i);
        }

        for (int i = 0; i < tail.length; i++) {
          final source = await _createAudioSource(tail[i]);
          await _player.insertAudioSource(currentIndex + 1 + i, source);
        }
        _syncCoverWarmer(currentIndex);
      } catch (e) {
        // The player and the model must never diverge; on any failure fall back
        // to a full, atomic rebuild from the authoritative _effectiveQueue.
        debugPrint('Tail mutation failed, rebuilding queue: $e');
        await _rebuildQueueInner(
          initialIndex: currentIndex,
          startPlaying: _player.playing,
        );
      }
    });
  }

  Future<void> playNext(Song song, {bool allowDuplicate = false}) async {
    await _runSerializedQueueMutation(() async {
      final currentIndex = _player.currentIndex ?? -1;
      final targetIndex = (currentIndex + 1).clamp(0, _effectiveQueue.length);

      final preventMerged =
          _ref?.read(settingsProvider).preventMergedDuplicates ?? true;
      final checkMergedSiblings = !allowDuplicate && preventMerged;

      final existingIdx = _findSongInQueue(song.filename,
          checkMergedSiblings: checkMergedSiblings);
      if (existingIdx != -1) {
        final existingItem = _effectiveQueue.removeAt(existingIdx);
        final actualTargetIndex =
            (existingIdx >= targetIndex) ? targetIndex : targetIndex - 1;
        _effectiveQueue.insert(actualTargetIndex, existingItem);
        try {
          await _player.moveAudioSource(existingIdx, actualTargetIndex);
        } catch (e) {
          _effectiveQueue.removeAt(actualTargetIndex);
          _effectiveQueue.insert(existingIdx, existingItem);
          rethrow;
        }
        _updateQueueNotifier();
        _savePlaybackState();
        await _updateCurrentSnapshotSongs();
        return;
      }

      final item = QueueItem(song: song);
      _effectiveQueue.insert(targetIndex, item);
      try {
        final source = await _createAudioSource(item);
        await _player.insertAudioSource(targetIndex, source);
      } catch (e) {
        _effectiveQueue.removeAt(targetIndex);
        rethrow;
      }
      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();
    });
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _runSerializedQueueMutation(() async {
      if (_effectiveQueue.isEmpty) return;
      if (oldIndex < 0 || oldIndex >= _effectiveQueue.length) return;

      int targetIndex = newIndex.clamp(0, _effectiveQueue.length);
      if (oldIndex < targetIndex) targetIndex -= 1;
      if (targetIndex < 0 || targetIndex >= _effectiveQueue.length) return;
      if (oldIndex == targetIndex) return;

      final item = _effectiveQueue.removeAt(oldIndex);
      _effectiveQueue.insert(targetIndex, item);
      try {
        await _player.moveAudioSource(oldIndex, targetIndex);
      } catch (e) {
        _effectiveQueue.removeAt(targetIndex);
        _effectiveQueue.insert(oldIndex, item);
        rethrow;
      }
      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();
    });
  }

  Future<void> removeFromQueue(int index) async {
    return _runSerializedQueueMutation(() async {
      if (_effectiveQueue.isEmpty) return;
      if (index < 0 || index >= _effectiveQueue.length) return;

      final removedItem = _effectiveQueue.removeAt(index);
      try {
        await _player.removeAudioSourceAt(index);
      } catch (e) {
        _effectiveQueue.insert(index, removedItem);
        rethrow;
      }
      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();
    });
  }

  Future<void> insertIntoQueue(int index, QueueItem item) async {
    await _runSerializedQueueMutation(() async {
      final targetIndex = index.clamp(0, _effectiveQueue.length);
      _effectiveQueue.insert(targetIndex, item);
      try {
        final source = await _createAudioSource(item);
        await _player.insertAudioSource(targetIndex, source);
      } catch (e) {
        _effectiveQueue.removeAt(targetIndex);
        rethrow;
      }
      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();
    });
  }

  Future<void> clearUpcoming() async {
    await _runSerializedQueueMutation(() async {
      final currentIndex = _player.currentIndex ?? -1;
      if (currentIndex < 0) return;
      if (currentIndex >= _effectiveQueue.length - 1) return;

      for (int i = _effectiveQueue.length - 1; i > currentIndex; i--) {
        if (i < 0 || i >= _effectiveQueue.length) continue;
        final removed = _effectiveQueue.removeAt(i);
        try {
          await _player.removeAudioSourceAt(i);
        } catch (e) {
          _effectiveQueue.insert(i, removed);
          rethrow;
        }
      }

      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();
    });
  }

  /// Plays a specific queued entry right now.
  ///
  /// An entry that is still upcoming is *moved* to just after the current
  /// track, so it exists once. An entry that has already played is *copied*
  /// there instead, leaving the played history intact. Either way nothing at or
  /// before the current track is disturbed, and playback then skips onto it.
  Future<void> jumpToQueueItem(String queueId) async {
    await _runSerializedQueueMutation(() async {
      final currentIndex = _player.currentIndex ?? -1;
      if (currentIndex < 0 || currentIndex >= _effectiveQueue.length) return;

      final sourceIndex =
          _effectiveQueue.indexWhere((item) => item.queueId == queueId);
      if (sourceIndex < 0 || sourceIndex == currentIndex) return;

      final targetIndex = currentIndex + 1;

      if (sourceIndex > currentIndex) {
        if (sourceIndex != targetIndex) {
          final item = _effectiveQueue.removeAt(sourceIndex);
          _effectiveQueue.insert(targetIndex, item);
          try {
            await _player.moveAudioSource(sourceIndex, targetIndex);
          } catch (e) {
            _effectiveQueue.removeAt(targetIndex);
            _effectiveQueue.insert(sourceIndex, item);
            rethrow;
          }
        }
      } else {
        // A fresh QueueItem, so the original entry keeps its own identity in
        // the played section rather than being yanked out of history.
        final copy = QueueItem(song: _effectiveQueue[sourceIndex].song);
        _effectiveQueue.insert(targetIndex, copy);
        try {
          final source = await _createAudioSource(copy);
          await _player.insertAudioSource(targetIndex, source);
        } catch (e) {
          _effectiveQueue.removeAt(targetIndex);
          rethrow;
        }
      }

      _updateQueueNotifier();
      _savePlaybackState();
      await _updateCurrentSnapshotSongs();

      await _player.seek(Duration.zero, index: targetIndex);
      await _player.play();
    });
  }

  Future<void> forceFlushCurrentStats() async {
    _flushStats(isTerminal: true);
    await _statsService.flush();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(forceFlushCurrentStats());
    _volumeMonitorService?.dispose();
    _positionSubscription?.cancel();
    _sequenceSubscription?.cancel();
    for (final sub in _trackedSubscriptions) {
      sub.cancel();
    }
    _trackedSubscriptions.clear();
    _fadeTimer?.cancel();
    _gapTimer?.cancel();
    _clearGapState();
    // Flush before the player goes away: the state is read from it, and a
    // coalesced write may still be pending.
    unawaited(savePlaybackState());
    _player.dispose();
    shuffleNotifier.dispose();
    preferredMediaModeNotifier.dispose();
    effectiveMediaModeNotifier.dispose();
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

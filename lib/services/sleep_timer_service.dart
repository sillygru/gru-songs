import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_player_manager.dart';

/// Enum representing the different sleep timer modes
enum SleepTimerMode {
  loopCurrent,
  playForTime,
  stopAfterCurrent,
  stopAfterTracks,
}

/// Service that manages sleep timer functionality
class SleepTimerService {
  static final SleepTimerService instance = SleepTimerService._internal();
  SleepTimerService._internal();

  Timer? _timer;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _sequenceStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playbackEventSub;
  Stopwatch? _elapsedTimeStopwatch;

  bool _isActive = false;
  bool _isShuttingDown = false;
  SleepTimerMode? _currentMode;
  VoidCallback? _onComplete;
  AudioPlayerManager? _audioManager;

  // State for stopAfterTracks
  int _remainingTracks = 0;
  int? _lastIndex;
  int? _stopAtEndIndex;

  // Store original loop mode to restore on cancel
  LoopMode? _originalLoopMode;

  // Test helper
  @visibleForTesting
  Future<void> Function()? mockExit;

  // Metadata for UI or queries
  DateTime? _startTime;
  int? _durationMinutes;

  /// Whether a sleep timer is currently active
  bool get isActive => _isActive;

  /// The current timer mode, or null if not active
  SleepTimerMode? get currentMode => _currentMode;

  /// Remaining minutes for time-based modes
  int? get remainingMinutes {
    if (_startTime == null || _durationMinutes == null) return null;
    final elapsed = DateTime.now().difference(_startTime!).inMinutes;
    return max(0, _durationMinutes! - elapsed);
  }

  /// Starts a sleep timer with the specified configuration
  void start({
    required SleepTimerMode mode,
    required int minutes,
    required int tracks,
    required bool letCurrentFinish,
    required AudioPlayerManager audioManager,
    required VoidCallback onComplete,
  }) {
    cancel();

    _isActive = true;
    _isShuttingDown = false;
    _currentMode = mode;
    _onComplete = onComplete;
    _audioManager = audioManager;
    _durationMinutes = minutes;
    _startTime = DateTime.now();
    _lastIndex = audioManager.player.currentIndex;

    // Store original loop mode to restore on cancel
    _originalLoopMode = audioManager.player.loopMode;

    switch (mode) {
      case SleepTimerMode.loopCurrent:
        _startLoopCurrent(minutes, audioManager);
        break;
      case SleepTimerMode.playForTime:
        _startPlayForTime(minutes, letCurrentFinish, audioManager);
        break;
      case SleepTimerMode.stopAfterCurrent:
        _startStopAfterCurrent(audioManager);
        break;
      case SleepTimerMode.stopAfterTracks:
        // Tracks input represents "N more tracks" (e.g. 1 means Current + 1)
        _startStopAfterTracks(tracks + 1, audioManager);
        break;
    }
  }

  void _startLoopCurrent(int minutes, AudioPlayerManager audioManager) {
    audioManager.player.setLoopMode(LoopMode.one);
    _startStopwatchTimer(minutes, audioManager);
  }

  void _startPlayForTime(
    int minutes,
    bool letCurrentFinish,
    AudioPlayerManager audioManager,
  ) {
    _startStopwatchTimer(
      minutes,
      audioManager,
      letCurrentFinish: letCurrentFinish,
    );
  }

  void _startStopAfterCurrent(AudioPlayerManager audioManager) {
    final currentIndex = audioManager.player.currentIndex;
    final duration = audioManager.player.duration;
    final position = audioManager.player.position;

    if (currentIndex == null) {
      _performShutdown(audioManager);
      return;
    }

    // Check if song is near end (within last 5% or 5 seconds, whichever is larger)
    if (duration != null && position > Duration.zero) {
      final nearEndThreshold = Duration(
        milliseconds: max(
          duration.inMilliseconds ~/ 20, // 5%
          5000, // 5 seconds
        ),
      );
      final timeRemaining = duration - position;

      if (timeRemaining <= nearEndThreshold) {
        // Song is almost over, treat as if it's already complete
        _performShutdown(audioManager);
        return;
      }
    }

    _stopAtEndIndex = currentIndex;
    _enableStopAtEndOfSong(audioManager);
  }

  void _startStopAfterTracks(
    int totalTracksToPlay,
    AudioPlayerManager audioManager,
  ) {
    if (totalTracksToPlay <= 1) {
      _startStopAfterCurrent(audioManager);
      return;
    }

    final currentIndex = audioManager.player.currentIndex;
    if (currentIndex == null) {
      _performShutdown(audioManager);
      return;
    }

    _remainingTracks = totalTracksToPlay - 1; // Subtract 1 for current track
    _lastIndex = currentIndex;
    _stopAtEndIndex = null;

    // Use playbackEventStream for more reliable index change detection
    _playbackEventSub = audioManager.player.playbackEventStream.listen((event) {
      final currentIndex = audioManager.player.currentIndex;
      if (currentIndex == null) return;

      // Check if index changed
      if (_lastIndex != null && currentIndex != _lastIndex) {
        // Calculate how many tracks we jumped
        final trackDelta = (currentIndex - _lastIndex!).abs();
        _remainingTracks -= trackDelta;
        _lastIndex = currentIndex;

        if (_remainingTracks <= 0) {
          // We should stop on this track
          _playbackEventSub?.cancel();
          _playbackEventSub = null;
          _enableStopAtEndOfSong(audioManager);
        }
      } else if (_lastIndex == null) {
        _lastIndex = currentIndex;
      }
    });

    // Also watch for song completion as fallback
    _playerStateSub = audioManager.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _remainingTracks--;
        if (_remainingTracks <= 0) {
          _performShutdown(audioManager);
        }
      }
    });
  }

  void _startStopwatchTimer(
    int minutes,
    AudioPlayerManager audioManager, {
    bool letCurrentFinish = false,
  }) {
    _elapsedTimeStopwatch = Stopwatch()..start();
    final targetDuration = Duration(minutes: minutes);

    // Use a periodic timer to check elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_elapsedTimeStopwatch == null) return;

      final elapsed = _elapsedTimeStopwatch!.elapsed;
      if (elapsed >= targetDuration) {
        _timer?.cancel();
        _timer = null;

        if (letCurrentFinish) {
          _enableStopAtEndOfSong(audioManager);
        } else {
          _performShutdown(audioManager);
        }
      }
    });
  }

  /// Enables the "stop at end of song" logic
  /// Pauses at Duration - 1 second to prevent auto-advance
  void _enableStopAtEndOfSong(AudioPlayerManager audioManager) {
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _sequenceStateSub?.cancel();

    final currentIndex = audioManager.player.currentIndex;
    _stopAtEndIndex = currentIndex;

    if (currentIndex == null) {
      _performShutdown(audioManager);
      return;
    }

    // Listen for sequence state changes (index changes)
    _sequenceStateSub = audioManager.player.sequenceStateStream.listen((state) {
      if (_isShuttingDown) return;

      final currentIndex = state?.currentIndex;
      if (_stopAtEndIndex != null &&
          currentIndex != null &&
          currentIndex != _stopAtEndIndex) {
        // Index changed - song ended and moved to next
        // Stop immediately before next song plays
        _performShutdown(audioManager);
      }
    });

    // Listen for completed state as fallback
    _playerStateSub = audioManager.player.playerStateStream.listen((state) {
      if (_isShuttingDown) return;

      if (state.processingState == ProcessingState.completed) {
        _performShutdown(audioManager);
      }
    });

    // Listen to position to stop before song ends (prevents auto-advance)
    _positionSub = audioManager.player.positionStream.listen((pos) {
      if (_isShuttingDown) return;

      // Check if index changed during playback
      final currentIdx = audioManager.player.currentIndex;
      if (_stopAtEndIndex != null &&
          currentIdx != null &&
          currentIdx != _stopAtEndIndex) {
        _performShutdown(audioManager);
        return;
      }

      final duration = audioManager.player.duration;
      if (duration != null && duration > const Duration(milliseconds: 500)) {
        // Stop 1 second before end to prevent auto-advance
        final threshold = duration > const Duration(seconds: 2)
            ? duration - const Duration(seconds: 1)
            : duration - const Duration(milliseconds: 500);

        if (pos >= threshold) {
          _performShutdown(audioManager);
        }
      }
    });
  }

  Future<void> _performShutdown(AudioPlayerManager audioManager) async {
    // Prevent multiple concurrent shutdowns
    if (!_isActive || _isShuttingDown) return;
    _isShuttingDown = true;

    // Cancel all subscriptions immediately to prevent race conditions
    _cleanupSubscriptions();

    try {
      // Reset loop mode immediately
      try {
        await audioManager.player.setLoopMode(LoopMode.off);
      } catch (e) {
        debugPrint("Error resetting loop mode: $e");
      }

      // Pause immediately
      await audioManager.player.pause();

      // Flush stats
      audioManager.didChangeAppLifecycleState(AppLifecycleState.paused);

      // Callback
      _onComplete?.call();

      // Wait 3 seconds
      await Future.delayed(const Duration(seconds: 3));

      // Check if we were cancelled during the wait
      if (!_isActive) return;

      // Mark timer as inactive
      // This ensures UI doesn't show active timer
      _isActive = false;
      _currentMode = null;

      // Stop player to dismiss notification and clear queue
      // Queue is auto-saved by AudioPlayerManager, stats already flushed above
      await audioManager.player.stop();

      // Short delay for UX (callback/snackbar to show)
      await Future.delayed(const Duration(milliseconds: 500));

      // App stays alive but in background - Android will kill it naturally when needed
      // Notification is dismissed, user can reopen app normally
    } catch (e) {
      debugPrint("Error during sleep timer shutdown: $e");
    }
  }

  void _cleanupSubscriptions() {
    _timer?.cancel();
    _timer = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _sequenceStateSub?.cancel();
    _sequenceStateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _playbackEventSub?.cancel();
    _playbackEventSub = null;
    _elapsedTimeStopwatch?.stop();
    _elapsedTimeStopwatch = null;
  }

  void _cleanupState({bool keepActiveForShutdown = false}) {
    _cleanupSubscriptions();
    _stopAtEndIndex = null;
    _lastIndex = null;
    _remainingTracks = 0;

    if (!keepActiveForShutdown) {
      _isActive = false;
      _isShuttingDown = false;
      _currentMode = null;
      _audioManager = null;
      _onComplete = null;
      _startTime = null;
      _durationMinutes = null;
      _originalLoopMode = null;
    }
  }

  void cancel() {
    // If we cancel, we should also reset loop mode if it was loopCurrent
    if (_audioManager != null) {
      try {
        // Restore original loop mode or default to off
        final loopMode = _originalLoopMode ?? LoopMode.off;
        _audioManager!.player.setLoopMode(loopMode);
      } catch (e) {
        // Ignore
      }
    }
    _cleanupState();
  }
}

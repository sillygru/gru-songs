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

  bool _isActive = false;
  SleepTimerMode? _currentMode;
  VoidCallback? _onComplete;
  AudioPlayerManager? _audioManager;

  // State for stopAfterTracks
  int _remainingTracks = 0;
  int? _lastIndex;
  int? _stopAtEndIndex;

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
    _currentMode = mode;
    _onComplete = onComplete;
    _audioManager = audioManager;
    _durationMinutes = minutes;
    _startTime = DateTime.now();
    _lastIndex = audioManager.player.currentIndex;

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
        // tracks input represents "N more tracks" (e.g. 1 means Current + 1)
        // Based on UI text "after N more songs", if user selects 1, it means current + 1.
        // Total tracks to play = tracks + 1.
        _startStopAfterTracks(tracks + 1, audioManager);
        break;
    }
  }

  void _startLoopCurrent(int minutes, AudioPlayerManager audioManager) {
    audioManager.player.setLoopMode(LoopMode.one);
    _timer = Timer(Duration(minutes: minutes), () {
      _performShutdown(audioManager);
    });
  }

  void _startPlayForTime(
      int minutes, bool letCurrentFinish, AudioPlayerManager audioManager) {
    _timer = Timer(Duration(minutes: minutes), () {
      if (letCurrentFinish) {
        _enableStopAtEndOfSong(audioManager);
      } else {
        _performShutdown(audioManager);
      }
    });
  }

  void _startStopAfterCurrent(AudioPlayerManager audioManager) {
    _enableStopAtEndOfSong(audioManager);
  }

  void _startStopAfterTracks(
      int totalTracksToPlay, AudioPlayerManager audioManager) {
    if (totalTracksToPlay <= 1) {
      _startStopAfterCurrent(audioManager);
      return;
    }

    _remainingTracks = totalTracksToPlay;
    _lastIndex = audioManager.player.currentIndex;

    // Listen for song changes
    _sequenceStateSub = audioManager.player.sequenceStateStream.listen((state) {
      final currentIndex = state.currentIndex;
      // If index changed
      if (currentIndex != null &&
          _lastIndex != null &&
          currentIndex != _lastIndex) {
        _remainingTracks--;
        _lastIndex = currentIndex;

        if (_remainingTracks <= 1) {
          // We are now on the last track
          _sequenceStateSub?.cancel();
          _sequenceStateSub = null;
          _enableStopAtEndOfSong(audioManager);
        }
      } else if (currentIndex != null && _lastIndex == null) {
        _lastIndex = currentIndex;
      }
    });
  }

  /// Enables the "stop at end of song" logic
  /// Pauses at Duration - 1 second
  void _enableStopAtEndOfSong(AudioPlayerManager audioManager) {
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _sequenceStateSub?.cancel();
    _stopAtEndIndex = audioManager.player.currentIndex;

    _sequenceStateSub = audioManager.player.sequenceStateStream.listen((state) {
      final currentIndex = state.currentIndex;
      if (_stopAtEndIndex != null &&
          currentIndex != null &&
          currentIndex != _stopAtEndIndex) {
        _performShutdown(audioManager);
      }
    });

    _playerStateSub = audioManager.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _performShutdown(audioManager);
      }
    });

    _positionSub = audioManager.player.positionStream.listen((pos) {
      if (_stopAtEndIndex != null &&
          audioManager.player.currentIndex != null &&
          audioManager.player.currentIndex != _stopAtEndIndex) {
        _performShutdown(audioManager);
        return;
      }
      final duration = audioManager.player.duration;
      if (duration != null && duration > const Duration(milliseconds: 500)) {
        final threshold = duration > const Duration(seconds: 1)
            ? duration - const Duration(seconds: 1)
            : Duration.zero;
        if (pos >= threshold) {
          _performShutdown(audioManager);
        }
      }
    });
  }

  Future<void> _performShutdown(AudioPlayerManager audioManager) async {
    // Prevent multiple calls
    if (!_isActive) return;
    _cleanupState(
        keepActiveForShutdown:
            true); // Cancel listeners but keep _isActive true for a moment

    try {
      // 1. Pause immediately (or at last second)
      await audioManager.player.pause();

      // 2. Flush stats
      audioManager.didChangeAppLifecycleState(AppLifecycleState.paused);

      // 3. Callback
      _onComplete?.call();

      // 4. Wait 3 seconds
      await Future.delayed(const Duration(seconds: 3));

      // 5. Kill app
      if (mockExit != null) {
        await mockExit!();
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        SystemNavigator.pop();
      } else {
        exit(0);
      }
    } catch (e) {
      debugPrint("Error during sleep timer shutdown: $e");
      if (mockExit == null) exit(0);
    }
  }

  void _cleanupState({bool keepActiveForShutdown = false}) {
    _timer?.cancel();
    _timer = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _sequenceStateSub?.cancel();
    _sequenceStateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _stopAtEndIndex = null;

    if (!keepActiveForShutdown) {
      _isActive = false;
      _currentMode = null;
      _audioManager = null;
      _startTime = null;
      _durationMinutes = null;
    }
  }

  void cancel() {
    // If we cancel, we should also reset loop mode if it was loopCurrent
    if (_currentMode == SleepTimerMode.loopCurrent && _audioManager != null) {
      try {
        _audioManager!.player.setLoopMode(LoopMode.off);
      } catch (e) {
        // Ignore
      }
    }
    _cleanupState();
  }
}

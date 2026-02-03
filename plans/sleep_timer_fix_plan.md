# Sleep Timer Fix Plan

## Current Issues Identified

### 1. **Stop After Current Song** (`_startStopAfterCurrent`)
**Problem:** Listens for `ProcessingState.completed` but this may fire AFTER the next song has already started playing due to just_audio's auto-advance behavior.

**Current Code:**
```dart
void _startStopAfterCurrent(AudioPlayerManager audioManager) {
  _playerStateSub = audioManager.player.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      _stop(audioManager);  // Too late - next song may already be playing
    }
  });
}
```

**Fix Required:** 
- Use `sequenceStateStream` to detect when current song is about to end
- Pause immediately when current song completes, BEFORE next song starts
- Skip to next but don't play it

### 2. **Stop After N Tracks** (`_startStopAfterTracks`)
**Problem:** Same issue - listens for `completed` state which fires after auto-advance has already started the next song.

**Current Code:**
```dart
void _startStopAfterTracks(int tracks, AudioPlayerManager audioManager) {
  _remainingTracks = tracks;
  _playerStateSub = audioManager.player.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      _remainingTracks--;
      if (_remainingTracks <= 0) {
        _stop(audioManager);  // Too late!
      }
    }
  });
}
```

**Fix Required:**
- Track current index via `sequenceStateStream`
- When index changes (song advances), decrement counter
- When counter reaches 0, pause immediately and skip to next without playing

### 3. **Play For Time with "Let Current Finish"** (`_waitForSongToFinish`)
**Problem:** Has race condition - seeks to next then stops, but the next song may start playing before pause takes effect.

**Current Code:**
```dart
void _waitForSongToFinish(AudioPlayerManager audioManager) {
  _playerStateSub?.cancel();
  _playerStateSub = audioManager.player.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      audioManager.player.pause();  // Race condition here
      if (audioManager.player.hasNext) {
        audioManager.player.seekToNext();  // May auto-play
      }
      _stop(audioManager);
    }
  });
}
```

**Fix Required:**
- Pause FIRST, then seek to next
- Ensure the player is in paused state before seeking

### 4. **Stats Flushing** (`_stop`)
**Current Code:**
```dart
Future<void> _stop(AudioPlayerManager audioManager) async {
  audioManager.player.setLoopMode(LoopMode.off);
  audioManager.player.pause();
  audioManager.didChangeAppLifecycleState(AppLifecycleState.paused);  // This flushes stats
  // ...
}
```

This looks correct - `didChangeAppLifecycleState(AppLifecycleState.paused)` triggers `_flushStats` and `_statsService.flush()`.

### 5. **App Termination** (`_stop`)
**Current Code:**
```dart
Future<void> _stop(AudioPlayerManager audioManager) async {
  // ...
  await Future.delayed(const Duration(seconds: 3));
  _exitApp();
  cancel();
}
```

This is correct but `cancel()` is called AFTER `_exitApp()` which may never execute on some platforms.

## Proposed Solution

### New Sleep Timer Implementation Strategy

```dart
class SleepTimerService {
  // ... existing fields ...
  
  // Track current song index to detect song changes
  int? _lastIndex;
  bool _shouldStopOnNextCompletion = false;
  
  void _startStopAfterCurrent(AudioPlayerManager audioManager) {
    // Get current index
    _lastIndex = audioManager.player.currentIndex;
    
    // Listen to sequence state to detect when we're about to change songs
    _playerStateSub = audioManager.player.sequenceStateStream.listen((state) {
      if (state == null) return;
      
      final currentIndex = state.currentIndex;
      
      // Check if song changed (index changed and we're playing)
      if (_lastIndex != null && 
          currentIndex != _lastIndex && 
          currentIndex > _lastIndex!) {
        // Song advanced - stop immediately before new song plays
        _stop(audioManager);
        return;
      }
      
      _lastIndex = currentIndex;
    });
  }
  
  void _startStopAfterTracks(int tracks, AudioPlayerManager audioManager) {
    _remainingTracks = tracks;
    _lastIndex = audioManager.player.currentIndex;
    
    _playerStateSub = audioManager.player.sequenceStateStream.listen((state) {
      if (state == null) return;
      
      final currentIndex = state.currentIndex;
      
      // Check if song advanced
      if (_lastIndex != null && 
          currentIndex != _lastIndex && 
          currentIndex > _lastIndex!) {
        _remainingTracks--;
        
        if (_remainingTracks <= 0) {
          // Stop immediately - don't let the new song play
          _stop(audioManager);
          return;
        }
      }
      
      _lastIndex = currentIndex;
    });
  }
  
  void _waitForSongToFinish(AudioPlayerManager audioManager) {
    _playerStateSub?.cancel();
    
    // Listen for completion
    _playerStateSub = audioManager.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Pause FIRST
        audioManager.player.pause();
        
        // Then seek to next without playing
        if (audioManager.player.hasNext) {
          // Use a microtask to ensure pause takes effect first
          Future.microtask(() async {
            await audioManager.player.seekToNext();
            await audioManager.player.pause();  // Ensure it stays paused
            _stop(audioManager);
          });
        } else {
          _stop(audioManager);
        }
      }
    });
  }
  
  Future<void> _stop(AudioPlayerManager audioManager) async {
    // Cancel all subscriptions first to prevent any new events
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _timer?.cancel();
    _timer = null;
    
    // Reset loop mode
    audioManager.player.setLoopMode(LoopMode.off);
    
    // Ensure playback is paused
    await audioManager.player.pause();
    
    // Flush stats
    audioManager.didChangeAppLifecycleState(AppLifecycleState.paused);
    
    // Call completion callback
    _onComplete?.call();
    
    // Wait 3 seconds then exit
    await Future.delayed(const Duration(seconds: 3));
    
    // Clean up state before exiting
    _isActive = false;
    _currentMode = null;
    _remainingTracks = 0;
    _onComplete = null;
    _audioManager = null;
    _startTime = null;
    _durationMinutes = null;
    _lastIndex = null;
    
    _exitApp();
  }
}
```

## Edge Cases to Handle

1. **Empty Queue:** If queue is empty, timer should still work and exit properly
2. **Last Song:** When on last song and timer ends, should not try to seek to next
3. **User Skips:** If user manually skips songs during "stop after N tracks", should still count correctly
4. **Pause/Resume:** Timer should continue even if user pauses playback
5. **Multiple Timer Starts:** Cancel existing timer before starting new one (already handled)
6. **App Backgrounding:** Timer should continue in background

## Test Plan

### Unit Tests
1. **Stop After Current Song:**
   - Timer starts, song completes, playback stops, next song not played
   - Stats are flushed
   - App exits after 3 seconds

2. **Stop After N Tracks:**
   - Timer starts with N=3, after 3 songs playback stops
   - 4th song is not played
   - Stats flushed, app exits

3. **Play For Time - Immediate Stop:**
   - Timer expires, playback stops immediately
   - Stats flushed, app exits

4. **Play For Time - Let Current Finish:**
   - Timer expires during song, waits for completion
   - Next song loaded but not played
   - Stats flushed, app exits

5. **Loop Current:**
   - Song loops for specified time
   - After time expires, loop mode reset
   - Playback stops, app exits

6. **Edge Cases:**
   - Empty queue
   - Last song in queue
   - User manually skips during countdown
   - Timer cancelled mid-operation

## Implementation Steps

1. Extract `SleepTimerService` to its own file (`lib/services/sleep_timer_service.dart`)
2. Fix all timer modes with proper song change detection
3. Ensure proper pause-before-seek ordering
4. Add comprehensive error handling
5. Write unit tests
6. Run all tests to verify

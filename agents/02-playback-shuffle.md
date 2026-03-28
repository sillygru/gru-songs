# Playback & Shuffle

## Core File

`lib/services/audio_player_manager.dart` - Central playback controller

## Responsibilities

- Playback control (play, pause, seek, skip)
- Queue management (original vs effective queue)
- Weighted shuffle algorithm
- Gapless playback
- Fade in/out transitions
- Volume monitoring
- Background playback integration
- Session history tracking

## Key Components

### Queue System
- `_originalQueue` - Base queue (e.g., folder/playlist order)
- `_effectiveQueue` - Modified queue after shuffle weights applied
- `_isRestrictedToOriginal` - Flag to limit auto-generation to original queue

### Shuffle State
- `ShuffleState` - Holds `ShuffleConfig` and history
- `HistoryEntry` - Tracks played songs with timestamps
- History limit: 200 songs default

## Shuffle Personalities

| Personality | Behavior |
|-------------|----------|
| `defaultMode` | Balanced weighting |
| `explorer` | High randomness, favors least-played |
| `consistent` | Low randomness, favors favorites |
| `custom` | Granular weight control |

## Custom Mode Settings

### Simple
- `avoidRepeatingSongs` - Penalize recently played songs
- `avoidRepeatingArtists` - Penalize same artist repeats
- `avoidRepeatingAlbums` - Penalize same album repeats
- `favorLeastPlayed` - Toggle least/most played preference

### Advanced Weights (-99 to +99, 0 = neutral)
- `leastPlayedWeight`
- `mostPlayedWeight`
- `favoritesWeight`
- `suggestLessWeight`
- `playlistSongsWeight`

## Key Algorithms

### Anti-Repeat
Penalizes songs recently played (up to 95% penalty based on recency).

### Streak Breaker
Reduces probability for same artist/album consecutive plays.

### Weighted Selection
Combines multiple factors:
- Play count (least/most played preference)
- Favorites multiplier (default 1.2x)
- Suggest-less multiplier (default 0.2x)
- Playlist membership bonus
- Anti-repeat penalties
- Streak breaker penalties

## Queue Behavior

### playSong() Logic
- If song exists in current queue: jumps to it WITHOUT rebuilding queue
- If song is NEW: builds fresh queue and optionally saves to history
- Detects "new queue" by comparing filename sets

### Queue History (Snapshots)
- Only saves when starting a TRULY new queue (not jumping within existing)
- Uses `QueueSnapshot` model stored in `queue_snapshot` table
- Song filenames stored in `queue_snapshot_song` junction table

### Pending Queue Replacement
- `setPendingQueueReplacement()` - queues songs to play after current song ends
- `replaceQueue()` - immediately replaces current queue (clears any pending)
- Triggered on `ProcessingState.completed` (queue finished) or song change

## Important Methods

```dart
// Play song (smart: jumps if in queue, builds new if not)
Future<void> playSong(
  Song song, {
  List<Song>? contextQueue,
  String? playlistId,
  bool startPlaying = true,
  bool forceLinear = false,
})

// Replace entire queue immediately
Future<void> replaceQueue(
  List<Song> songs, {
  String? playlistId,
  bool forceLinear = false,
  bool saveSnapshot = true,
})

// Queue for later playback
void setPendingQueueReplacement(List<Song> songs, {String? playlistId})

// Cancel pending queue
void cancelPendingQueueReplacement()
```

## Related Files

- `lib/models/shuffle_config.dart` - Config and state models
- `lib/services/stats_service.dart` - Play count tracking
- `test/shuffle_logic_test.dart` - Shuffle algorithm tests
- `test/personality_logic_test.dart` - Personality behavior tests

## Constraints

- Always run shuffle tests after modifying algorithm
- `AudioPlayerManager` is decoupled from `UserDataNotifier` - updates pushed, not pulled
- File-based identity: songs identified by filename, not ID

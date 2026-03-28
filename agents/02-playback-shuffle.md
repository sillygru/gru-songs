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

## Important Methods

```dart
// Initialize shuffle for a queue
void _initShuffle(List<QueueItem> queue)

// Generate weighted queue
List<QueueItem> _generateWeightedQueue()

// Handle song completion (triggers next song + stats)
Future<void> _onSongComplete()

// Play specific song
Future<void> playSong(Song song, [List<Song>? contextQueue])
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

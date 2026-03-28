# Models

Core data entities used throughout the application. All models use `Equatable` for value equality.

## Song (`song.dart`)

Represents a single audio track.

### Fields
| Field | Type | Description |
|-------|------|-------------|
| `title` | String | Track title |
| `artist` | String | Artist name |
| `album` | String | Album name |
| `filename` | String | **Unique identifier** (file path) |
| `url` | String | File URI |
| `coverUrl` | String? | Cached album art path |
| `hasLyrics` | bool | Whether lyrics are available |
| `playCount` | int | Number of plays |
| `duration` | Duration? | Track length |
| `mtime` | double? | File modification time |
| `createdEpochSec` | double? | File creation timestamp |
| `songDateEpochSec` | double? | Track release date |

### Computed Properties
- `hasVideo` - Returns true if file extension is a video format

### Video Extensions
`.mp4`, `.m4v`, `.mov`, `.mkv`, `.webm`, `.avi`, `.3gp`

## LyricLine (`song.dart`)

Represents a single line of synced lyrics.

### Fields
- `time` - Timestamp for display
- `text` - Lyric text
- `isSynced` - Whether timestamp is accurate

### Static Methods
- `parse(String content)` - Parses LRC format lyrics

## ShuffleConfig (`shuffle_config.dart`)

Configuration for shuffle behavior.

### Fields
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | bool | false | Shuffle on/off |
| `antiRepeatEnabled` | bool | true | Penalize recent songs |
| `streakBreakerEnabled` | bool | true | Prevent artist/album streaks |
| `favoriteMultiplier` | double | 1.2 | Boost for favorites |
| `suggestLessMultiplier` | double | 0.2 | Reduction for suggest-less |
| `historyLimit` | int | 200 | Max history entries |
| `personality` | ShufflePersonality | defaultMode | Preset mode |

### Custom Mode - Simple
- `avoidRepeatingSongs` - Penalize recently played songs
- `avoidRepeatingArtists` - Penalize same artist
- `avoidRepeatingAlbums` - Penalize same album
- `favorLeastPlayed` - Favor least played songs

### Custom Mode - Advanced (-99 to +99)
- `leastPlayedWeight`
- `mostPlayedWeight`
- `favoritesWeight`
- `suggestLessWeight`
- `playlistSongsWeight`

## ShufflePersonality (`shuffle_config.dart`)

Enum defining shuffle behavior presets.

```dart
enum ShufflePersonality {
  defaultMode,   // Balanced
  explorer,      // High randomness, least-played focus
  consistent,    // Low randomness, favorites focus
  custom         // Manual weight configuration
}
```

## ShuffleState (`shuffle_config.dart`)

Runtime state for shuffle system.

### Fields
- `config` - Current `ShuffleConfig`
- (Future: history list, last played tracking)

## HistoryEntry (`shuffle_config.dart`)

Tracks a played song in shuffle history.

### Fields
- `filename` - Song identifier
- `timestamp` - When it was played (seconds since epoch)

## QueueItem (`queue_item.dart`)

Represents a song in the playback queue.

### Fields
- `queueId` - Unique queue entry ID (UUID)
- `song` - The `Song` object
- `isPriority` - Whether this is a priority song (e.g., user-selected next)

## QueueSnapshot (`queue_snapshot.dart`)

Saved state of a queue for restoration.

### Fields
- `id` - Snapshot identifier (UUID)
- `name` - Display name
- `createdAt` - Creation timestamp (epoch seconds)
- `songFilenames` - List of song filenames (not QueueItem objects)
- `source` - Origin type (playlist, folder, shuffle, etc.)

### Computed Properties
- `createdDateTime` - Converts timestamp to DateTime
- `displayDate` - Human-readable date ("Today at 3:45 PM", "Yesterday at...", "Jan 15 at...")

## Playlist (`playlist.dart`)

User-created playlist.

### Fields
- `id` - Unique identifier (UUID)
- `name` - Display name
- `description` - Optional description
- `isRecommendation` - Whether this is an auto-generated recommendation playlist
- `createdAt` - Creation timestamp (epoch seconds)
- `updatedAt` - Last update timestamp (epoch seconds)
- `songs` - List of `PlaylistSong` objects

### PlaylistSong
- `songFilename` - Song identifier
- `addedAt` - When added to playlist (epoch seconds)

## MoodTag (`mood_tag.dart`)

Emotional/mood categorization.

### Fields
- `id` - Unique identifier (UUID)
- `name` - Display name (e.g., "Happy", "Melancholic")
- `normalizedName` - Lowercase, normalized version for matching
- `isPreset` - Whether this is a built-in preset tag
- `createdAt` - Creation timestamp (epoch seconds)

## SearchFilterState (`search_filter.dart`)

Filter configuration for search.

### Fields
- `all` - Search all types
- `songs` - Include songs in results
- `artists` - Include artists
- `albums` - Include albums
- `lyrics` - Include lyric matches

## SearchResult (`search_result.dart`)

Search result entry.

### Fields
- `song` - Matched song
- `lyricsMatch` - Lyric match details (if applicable)
- `matchedFilters` - Which filters matched

## LyricMatch (`search_result.dart`)

Details of a lyric match.

### Fields
- `matchedText` - The matched portion
- `fullLine` - Complete lyric line containing match

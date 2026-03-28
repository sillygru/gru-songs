# Data Layer

## Database Service

`lib/services/database_service.dart`

### Databases

| Database | File | Purpose |
|----------|------|---------|
| Stats | `wispie_stats.db` | Play counts, listening history |
| User Data | `wispie_data.db` | Favorites, hidden, settings |

### Schema Overview

**Stats Database (`wispie_stats.db`):**
- `playsession` - Play sessions
- `playevent` - Individual play events

**User Data Database (`wispie_data.db`):**
- `userdata` - Single-user metadata
- `favorite` - Favorite song filenames
- `suggestless` - Songs to suggest less
- `hidden` - Hidden song filenames
- `song` - Cached song metadata
- `playlist` - Playlist definitions
- `playlist_song` - Playlist song mappings
- `merged_song_group` - Merge group definitions
- `merged_song` - Songs in merge groups
- `recommendation_preference` - Custom titles and pinned states
- `recommendation_removal` - Dismissed recommendations
- `mood_tag` - Mood tags (id, name, normalized_name, is_preset)
- `song_mood` - Song to mood mappings
- `queue_snapshot` - Queue snapshot definitions
- `queue_snapshot_song` - Songs in queue snapshots

### Key Methods

```dart
// Initialize (handles migration from user-specific DBs)
Future<bool> init()

// Stats operations
Future<void> updatePlayCount(String filename, int count)
Future<List<PlayStat>> getPlayStats()

// User data operations
Future<void> addFavorite(String filename)
Future<void> removeFavorite(String filename)
Future<List<String>> getFavorites()

// Playlist operations
Future<Playlist?> createPlaylist(String name)
Future<void> addSongToPlaylist(String playlistId, String filename)
```

### Migration

Automatically migrates from user-specific databases (`{username}_data.db`) to single-user databases (`wispie_data.db`) on first run after upgrade.

## Cache Service

`lib/services/cache_service.dart`

### Responsibilities
- Image caching (album art, video thumbnails)
- Metadata caching
- Cache invalidation on file changes

### Implementation
- Uses `flutter_cache_manager` for disk caching
- In-memory cache for frequently accessed data
- Automatic cleanup of stale entries

### Key Methods

```dart
// Initialize cache directories
Future<void> init()

// Get cached image
Future<File?> getImage(String key)

// Cache image
Future<void> cacheImage(String key, File image)

// Invalidate cache entry
Future<void> invalidate(String key)
```

## Key Services

### Scanner Service (`scanner_service.dart`)
- Filesystem scanning for audio files
- Metadata extraction via `audio_metadata_reader`
- Video file handling (extracts audio streams)
- Progress reporting during scans

### Library Logic (`library_logic.dart`)
- Core CRUD operations for songs
- Song add/remove/update logic
- Thumbnail generation coordination
- Merged song group management

### FFmpeg Service (`ffmpeg_service.dart`)
- Lyrics extraction from audio files
- Audio format conversions
- Audio manipulations

### File Manager Service (`file_manager_service.dart`)
- File deletion
- File renaming
- Metadata writing via `metadata_god`
- Permission handling

### Stats Service (`stats_service.dart`)
- Listening duration tracking (how long each song was played)
- Listening history recording
- Statistics aggregation

**playevent table columns:**
- `song_filename` - File path
- `timestamp` - Unix timestamp
- `duration_played` - Seconds listened
- `total_length` - Song duration in seconds
- `play_ratio` - Duration / total_length
- `foreground_duration` - Foreground playback time
- `background_duration` - Background playback time

### Cache Service (`cache_service.dart`)
- Image caching (album art, video thumbnails)
- Blurred cover cache for UI
- Cache size calculation
- Automatic cleanup of legacy caches

### Storage Service (`storage_service.dart`)
- Music folder management
- Setup state persistence
- Local/remote mode switching

### Backup Service (`backup_service.dart`)
- Manual library backup creation
- Backup restoration
- Export/import functionality

### Auto Backup Service (`auto_backup_service.dart`)
- Scheduled automatic backups
- Backup retention management

### Sleep Timer Service (`sleep_timer_service.dart`)
- Sleep timer with countdown
- Fade-out on timer expiry

### Waveform Service (`waveform_service.dart`)
- Audio waveform generation
- Waveform caching

### Color Extraction Service (`color_extraction_service.dart`)
- Album art color palette extraction
- Dominant color calculation for UI theming

### Bulk Metadata Service (`bulk_metadata_service.dart`)
- Batch metadata operations
- Transaction-style updates

### Data Export Service (`data_export_service.dart`)
- Library data export
- Statistics export

### Database Optimizer Service (`database_optimizer_service.dart`)
- Database vacuuming
- Performance optimization

### Storage Analysis Service (`storage_analysis_service.dart`)
- Storage usage analysis
- Cache size calculation

### Volume Monitor Service (`volume_monitor_service.dart`)
- Volume level monitoring
- Loudness detection

### Screen Wake Lock Service (`screen_wake_lock_service.dart`)
- Prevents screen sleep during playback

### Auth Service (`auth_service.dart`)
- Simple local authentication
- Username-based sessions

### Telemetry Service (`telemetry_service.dart`)
- Anonymous usage statistics (if enabled)

### Namida Import Service (`namida_import_service.dart`)
- Import data from Namida music player

### Android Storage Service (`android_storage_service.dart`)
- Android-specific storage access
- SAF (Storage Access Framework) integration

## Data Flow

```
FileSystem
    |
    v
ScannerService -> Metadata Extraction -> Song Objects
    |
    v
DatabaseService <- Persistence
    |
    v
CacheService <- Caching
    |
    v
providers.dart (songsProvider) -> UI
```

## Repository Pattern

`lib/data/repositories/`

- `song_repository.dart` - Lyrics extraction via FFmpeg
- `search_index_repository.dart` - Search index operations

## Important Notes

- Database is singleton pattern (`DatabaseService.instance`)
- All DB operations are async
- Cache service is singleton (`CacheService.instance`)
- File operations require storage permissions (handled by `permission_handler`)

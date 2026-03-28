# Library State

## Core Files

- `lib/providers/providers.dart` - Main provider orchestration
- `lib/providers/user_data_provider.dart` - User preferences and stats

## songsProvider (AsyncNotifier)

The source of truth for the song library. Located in `providers.dart`.

### Responsibilities
- File scanning and library population
- Background library updates
- Bulk actions (delete, rename, metadata edits)
- Merge group management
- Search index maintenance

### Key Operations

```dart
// Scan filesystem for audio files
Future<void> scanLibrary()

// Bulk delete songs
Future<void> deleteSongs(List<String> filenames)

// Bulk rename songs
Future<void> renameSongs(Map<String, String> filenameMap)

// Update metadata
Future<void> updateMetadata(List<Song> songs)

// Add/remove merge groups
Future<void> addMergeGroup(String groupId, List<String> filenames)
```

## user_data_provider.dart

Manages `UserDataState` via `UserDataNotifier`.

### Stored Data
- Favorites (list of filenames)
- Hidden songs (list of filenames)
- Suggest-less songs (list of filenames)
- Playlists (list of `Playlist` objects)
- Mood tags (list of `MoodTag` objects)
- Song mood mappings (map: filename -> mood IDs)
- Merged groups (map: group ID -> filenames)
- Merged group priorities (map: group ID -> priority filename)
- Recommendation preferences (custom titles, pinned states)
- Removed recommendations (list of filenames)

### Key Methods

```dart
// Toggle favorite status
void toggleFavorite(String filename)

// Toggle hidden status
void toggleHidden(String filename)

// Add to suggest-less
void addSuggestLess(String filename)

// Merge group operations
bool isMerged(String filename)
String? getMergedGroupId(String filename)
List<String> getMergedSiblings(String filename)

// Mood operations
List<String> moodsForSong(String filename)
bool songHasAnyMood(String filename, Set<String> moodIds)
```

## Scanner Service

`lib/services/scanner_service.dart`

- Scans directories for audio files
- Extracts metadata via `audio_metadata_reader`
- Handles video files (extracts audio)
- Returns list of `Song` objects

## Bulk Metadata Service

`lib/services/bulk_metadata_service.dart`

- Batch metadata operations
- Metadata writing via `metadata_god`
- Transaction-style updates

## File Operations

All file operations go through `lib/services/file_manager_service.dart`:

- File deletion
- File renaming
- Metadata writing
- Permission handling

## State Flow

```
FileSystem -> ScannerService -> songsProvider -> UI
                                   |
                                   v
                            UserDataNotifier (favorites, hidden, etc.)
```

## Important Notes

- Songs identified by **filename**, not ID
- `songsProvider` is an `AsyncNotifier` - use `ref.watch()` for UI, `ref.read()` for actions
- Bulk operations are atomic where possible
- Cache invalidation handled automatically after mutations

## Related Files

- `lib/services/cache_service.dart` - Cache invalidation after updates
- `lib/domain/services/search_service.dart` - Search index updates
- `lib/models/song.dart` - Song entity definition

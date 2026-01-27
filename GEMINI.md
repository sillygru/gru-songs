# GEMINI.md

This file provides guidance for Gemini when working with code in this repository.

## Essential Commands

### Flutter (Frontend)
```bash
# Install dependencies
flutter pub get

# Run the app (debug mode)
flutter run

# Run tests
flutter test

# Analyze code
flutter analyze

# Check formatting
dart format --set-exit-if-changed .

# Format code
dart format .

# Build for release
flutter build apk --release           # Android
flutter build ios --release           # iOS
flutter build macos --release         # macOS

# Run specific test file
flutter test test/shuffle_logic_test.dart
```

### Version Management
```bash
# Update version across the codebase
python update_version.py
```

## Architecture Overview

### Local-First Architecture
This project is a **fully offline local music player**:
- **Primary Mode**: Fully offline local music player with local filesystem scanning
- **Data Storage**: All data stored locally in SQLite databases

### Frontend (Flutter)
**State Management**: `flutter_riverpod` with a clean MVVM/Repository pattern
- **Providers** (`lib/providers/`): Riverpod providers for dependency injection and state management
- **Services** (`lib/services/`): Core business logic
- **Models** (`lib/models/`): Data structures (Song, QueueItem, ShuffleState, etc.)
- **Repositories** (`lib/data/repositories/`): Data source abstraction layer
- **Presentation** (`lib/presentation/`): UI screens and widgets

**Key Services**:
- `AudioPlayerManager`: Central playback controller with weighted shuffle algorithm supporting multiple "personalities" (Default, Explorer, Consistent), anti-repeat logic, and streak breaking
- `CacheService`: V3 cache implementation with instant cache-first serving, background validation, and atomic file replacement
- `ScannerService`: Local filesystem scanner for music metadata extraction
- `DatabaseService`: SQLite-based local storage for stats and user data
- `StatsService`: Tracks play events with foreground/background duration tracking
- `AuthService`: Simple local authentication with username

**Critical Components**:
- **Provider Decoupling**: `AudioPlayerManager` and `UserDataNotifier` are intentionally decoupled to prevent `CircularDependencyError`. User data updates are pushed to the manager, not pulled.

### Shuffle Algorithm
The shuffle system is highly sophisticated:
- **Weighted Selection**: Uses play counts, favorites, and suggest-less preferences
- **Personalities**: Three modes (Default, Explorer, Consistent) with different randomness levels
- **Anti-Repeat**: History-based probability reduction (up to 95% penalty)
- **Streak Breaker**: Reduces probability for same artist/album repeats
- **Persistence**: Shuffle state (including personality, config, and history) stored locally

### Data Flow
1. **Local Scan**: `ScannerService` scans filesystem → stores in `StorageService`
2. **Playback**: User selects song → `AudioPlayerManager` manages queue and stats
3. **Stats Tracking**: Foreground/background duration → stored in `DatabaseService`

## Critical Constraints

### Never Commit Without Permission
**NEVER** run `git commit`, `git push`, or any version control commands unless explicitly asked by the user. This is a strict constraint.

### Environment Awareness
Use relative paths or mock settings for local development.

### Playback Position Handling
Position is only resumed for the specific song that was last playing when the app closed. New song selections always start at position 0. Do not change this behavior.

### File-Based User Data
User data (stats, favorites, suggest-less) is purely based on filenames. Renaming a file resets all associated data. This is by design.

## Testing Strategy

### Flutter Tests
Located in `test/`:
- `shuffle_logic_test.dart`: Shuffle algorithm validation
- `personality_logic_test.dart`: Personality mode behavior
- `queue_test.dart`: Queue management
- `selection_sync_test.dart`: Selection synchronization
- `scanner_service_test.dart`: Filesystem scanning
- Test mocks use `mockito` with `build_runner` for code generation

### CI/CD
GitHub Actions workflow (`.github/workflows/flutter_tests.yml`) runs on push/PR:
1. Format check: `dart format --set-exit-if-changed .`
2. Static analysis: `flutter analyze`
3. Tests: `flutter test`

## Code Conventions

### Comment Policy
Following user rules, do NOT add:
1. Temporary comments (e.g., "New:", "Changed this to that")
2. Useless comments that just repeat the code (e.g., `CONSTANT TIME = 0.5 // the time is 0.5 seconds`)
3. LLM-specific comments (e.g., "user request", "note: replace this with that")

### Platform-Specific Code
- **Desktop & iPad**: Include volume slider in `NowPlayingBar` and `PlayerScreen`
- **Android**: Uses `AudioServiceActivity`, requires `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission
- **iOS**: Requires `UIBackgroundModes: audio`, `NSAppTransportSecurity` allows arbitrary loads

## Common Patterns

### Adding a New Screen
1. Create screen file in `lib/presentation/screens/`
2. Create provider in `lib/providers/` if needed
3. Add navigation in `MainScreen` or parent screen
4. Follow Material 3 design with dark theme (`Color(0xFF121212)` background)

### Modifying Shuffle Logic
Changes to shuffle must be coordinated between:
- `lib/services/audio_player_manager.dart`: Client-side implementation
- `lib/models/shuffle_config.dart`: Configuration model

## Important File Locations

### Configuration
- `pubspec.yaml`: Flutter dependencies and version (format: `Major.Normal.Bugfix+build`)
- `analysis_options.yaml`: Dart linter configuration

### Entry Points
- `lib/main.dart`: Flutter app initialization with cache setup and audio session config

### Key Models
- `lib/models/song.dart`: Song data structure
- `lib/models/queue_item.dart`: Queue entry with metadata
- `lib/models/shuffle_config.dart`: Shuffle state and personality configuration

### Platform-Specific
- `android/app/src/main/AndroidManifest.xml`: Android permissions and configuration
- `ios/Runner/Info.plist`: iOS permissions and ATS configuration
- `macos/Runner/Info.plist`: macOS permissions

All user-specific requests require `x-username` header.

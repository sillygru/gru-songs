# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

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
When prompted, enter the old version (e.g., `6.3.2`) and new version (e.g., `6.4.0`). This automatically updates all version references across the project, including pubspec.yaml and native platform files.

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

- **DatabaseService**: SQLite-based local storage for stats and user data
- **AudioPlayerManager**: Handles audio playback and queue management
- **StatsService**: Tracks listening statistics locally
- **AuthService**: Simple local authentication with username
- **StorageService**: Manages local app settings and preferences

### Data Flow

1. **Library Scan**: User selects music folder → ScannerService indexes files
2. **Playback**: User selects song → AudioPlayerManager plays → StatsService tracks
3. **User Data**: Favorites, playlists, and stats stored locally in SQLite
4. **Shuffle**: Personality system learns from listening patterns

## Development Guidelines

### File Organization

- `/lib/models/`: Data models (Song, Playlist, etc.)
- `/lib/services/`: Core business logic
- `/lib/providers/`: Riverpod state management
- `/lib/presentation/`: UI components and screens

### Testing

- Unit tests in `/test/`
- Run with `flutter test`
- Focus on core business logic and data models

### Local Development

The app is designed to work entirely locally. No server configuration needed for development.

## Common Tasks

### Adding New Features

1. Define models in `/lib/models/`
2. Implement service logic in `/lib/services/`
3. Create UI components in `/lib/presentation/`
4. Add state management with Riverpod providers
5. Write tests for new functionality

### Debugging Tips

- Use Flutter DevTools for debugging
- Check database contents with SQLite browser tools
- Monitor logs with `debugPrint()` statements

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



### Key Endpoints
- **Auth**: `/auth/signup`, `/auth/login`, `/auth/update-password`, `/auth/update-username`
- **User Data**: `/user/favorites`, `/user/suggest-less`, `/user/shuffle` (bidirectional sync)
- **Stats**: `/stats/track`, `/stats/summary`, `/stats/fun`
- **Database**: `/user/db/{db_type}` (GET/POST for `stats`, `data`, `final_stats` SQLite files)

All user-specific requests require `x-username` header.

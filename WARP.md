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

### Python Backend (Server)
```bash
# Install dependencies
pip install -r server/requirements.txt

# Run the server
python server/main.py

# Run tests
pytest server/tests/

# Run specific test
pytest server/tests/test_sync.py
```

### Version Management
```bash
# Update version across the codebase
python update_version.py
```
When prompted, enter the old version (e.g., `6.3.2`) and new version (e.g., `6.4.0`). This automatically updates all version references across the project, including pubspec.yaml and native platform files.

## Architecture Overview

### Hybrid Architecture: Offline-First with Optional Sync
This project uses a **dual-architecture approach**:
- **Primary Mode**: Fully offline local music player with local filesystem scanning
- **Optional Mode**: Sync stats and user preferences to a private FastAPI server

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
- `DatabaseService`: SQLite-based local storage for stats and user data with bidirectional server sync
- `StatsService`: Tracks play events with foreground/background duration tracking
- `UserDataService`: Manages favorites, suggest-less preferences, and shuffle state

**Critical Components**:
- **Provider Decoupling**: `AudioPlayerManager` and `UserDataNotifier` are intentionally decoupled to prevent `CircularDependencyError`. User data updates are pushed to the manager, not pulled.
- **TLS Workaround**: Custom `HttpOverrides` in `main.dart` and custom `IOClient` in `api_service.dart` are essential to prevent `HandshakeException` when connecting to Tailscale Funnel URLs from mobile devices. **Do not remove these**.

### Backend (Python/FastAPI)
**Structure**:
- `main.py`: API routes, lifespan management, and Discord bot initialization
- `user_service.py`: Auth, stats aggregation, and bidirectional database sync
- `backup_service.py`: Automated backup scheduler with MD5-based change detection
- `discord_bot.py`: Discord integration for logging and admin commands
- `database_manager.py`: SQLite database operations
- `services.py`: Music service (mostly deprecated in offline-first mode)

**Key Features**:
- Lifespan handlers for robust startup/shutdown
- Background stats flushing (every 5 minutes)
- Automated backups (every 6 hours) with MD5 optimization
- Discord bot commands: `!backup [true/false]`, `!stats [username]`
- Per-user SQLite databases: `{username}_data.db`, `{username}_stats.db`, `{username}_final_stats.json`

### Shuffle Algorithm
The shuffle system is highly sophisticated:
- **Weighted Selection**: Uses play counts, favorites, and suggest-less preferences
- **Personalities**: Three modes (Default, Explorer, Consistent) with different randomness levels
- **Anti-Repeat**: History-based probability reduction (up to 95% penalty)
- **Streak Breaker**: Reduces probability for same artist/album repeats
- **Persistence**: Shuffle state (including personality, config, and history) syncs bidirectionally with server

### Data Flow
1. **Local Scan**: `ScannerService` scans filesystem → stores in `StorageService`
2. **Playback**: User selects song → `AudioPlayerManager` manages queue and stats
3. **Stats Tracking**: Foreground/background duration → buffered in `DatabaseService`
4. **Sync**: Periodic or pull-to-refresh triggers bidirectional sync with server
5. **Backup**: Server periodically backs up user databases with change detection

## Critical Constraints

### Never Commit Without Permission
**NEVER** run `git commit`, `git push`, or any version control commands unless explicitly asked by the user. This is a strict constraint.

### Environment Awareness
The development environment is not the production server. Avoid absolute paths like `/home/sillygru/` which are server-specific. Use relative paths or mock settings. If errors reference `/home/sillygru`, it's because the code is incorrectly trying to use server environment variables (`.env`) during local development.

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

### Python Tests
Located in `server/tests/`:
- `test_sync.py`: Database synchronization
- `test_backup.py`: Backup service logic
- `test_shuffle_persistence.py`: Server-side shuffle state
- `test_fun_stats.py`: Statistics aggregation
- Run with `pytest server/tests/`

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

### Adding a New API Endpoint
1. Define model in `server/models.py`
2. Add route in `server/main.py`
3. Implement logic in `server/user_service.py` or appropriate service
4. Add corresponding method in `lib/services/api_service.dart`
5. Update repository/provider layer if needed

### Modifying Shuffle Logic
Changes to shuffle must be coordinated between:
- `lib/services/audio_player_manager.dart`: Client-side implementation
- `lib/models/shuffle_config.dart`: Configuration model
- `server/user_service.py`: Server-side shuffle state storage
- Ensure bidirectional sync remains intact

## Important File Locations

### Configuration
- `pubspec.yaml`: Flutter dependencies and version (format: `Major.Normal.Bugfix+build`)
- `server/requirements.txt`: Python dependencies
- `server/settings.py`: Server configuration (uses `.env` for secrets)
- `analysis_options.yaml`: Dart linter configuration

### Entry Points
- `lib/main.dart`: Flutter app initialization with cache setup and audio session config
- `server/main.py`: FastAPI server with lifespan handlers

### Key Models
- `lib/models/song.dart`: Song data structure
- `lib/models/queue_item.dart`: Queue entry with metadata
- `lib/models/shuffle_config.dart`: Shuffle state and personality configuration

### Platform-Specific
- `android/app/src/main/AndroidManifest.xml`: Android permissions and configuration
- `ios/Runner/Info.plist`: iOS permissions and ATS configuration
- `macos/Runner/Info.plist`: macOS permissions

## Server API (Optional Sync Mode)

Base URL: `http://samsung-sm-sm-a127f.tail6d7f03.ts.net:9000` (configurable via `StorageService`)

### Key Endpoints
- **Auth**: `/auth/signup`, `/auth/login`, `/auth/update-password`, `/auth/update-username`
- **User Data**: `/user/favorites`, `/user/suggest-less`, `/user/shuffle` (bidirectional sync)
- **Stats**: `/stats/track`, `/stats/summary`, `/stats/fun`
- **Database**: `/user/db/{db_type}` (GET/POST for `stats`, `data`, `final_stats` SQLite files)

All user-specific requests require `x-username` header.

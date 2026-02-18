# Agents.md - Project Context for AI Agents

This file provides a structured overview of the `gru-songs` codebase to help agentic LLMs understand the architecture, key components, and development workflows.

## Architecture Overview

The project follows a **Local-First** approach, functioning as a fully offline music player. It uses Flutter with a clean MVVM/Repository pattern and Riverpod for state management.

### Tech Stack
- **Framework**: Flutter (Dart)
- **State Management**: `flutter_riverpod` (Notifier, AsyncNotifier, and Provider)
- **Audio Engine**: `just_audio` & `just_audio_background`
- **Database**: SQLite via `sqflite` (handled in `DatabaseService`)
- **Metadata**: `metadata_god`, `audio_metadata_reader`, and `ffmpeg_kit_flutter_new_min`
- **Processing**: `FFmpegService` for lyrics extraction and audio manipulations.

## Directory Structure & Key Files

### Core Logic (`lib/`)
- `lib/services/`: **Primary logic layer.**
    - `audio_player_manager.dart`: Central playback controller, queue management, and weighted shuffle algorithm.
    - `scanner_service.dart`: Scans the filesystem for audio files and extracts metadata.
    - `database_service.dart`: Singleton for SQLite operations.
    - `cache_service.dart`: High-performance caching for images and metadata.
    - `file_manager_service.dart`: Handles file deletions, renames, and metadata writes.
- `lib/providers/`: **State and Dependency Injection.**
    - `providers.dart`: Contains `songsProvider` (`AsyncNotifier`), which is the source of truth for the song library. It handles scanning, background updates, and bulk actions.
    - `user_data_provider.dart`: Manages `UserDataState` (favorites, hidden songs, suggest-less, play counts).
    - `auth_provider.dart`: Simple local auth (username-based).
- `lib/data/`: Data source abstraction.
    - `repositories/song_repository.dart`: Currently used for lyrics extraction via FFmpeg.
    - `models/search_index_entry.dart`: Specific models for indexing and search.
- `lib/domain/`: Domain-specific logic.
    - `services/search_service.dart`: Logic for filtering and searching the library.
- `lib/models/`: Core entities used across the app (`Song`, `Playlist`, `QueueItem`, `ShuffleConfig`).

### Testing (`test/`)
- `test/shuffle_logic_test.dart`: Critical for validating shuffle behavior.
- `test/scanner_service_test.dart`: Validates filesystem scanning.
- `test/test_helpers.dart`: Contains mocks and setup for unit tests.
- `test/selection_sync_test.dart`: Validates selection logic.

## How to Search This Repo

1.  **Playback & Shuffle**: `lib/services/audio_player_manager.dart` is the heart of playback.
2.  **Library State**: `lib/providers/providers.dart` -> `songsProvider`. This is where file scanning and library modifications (delete/rename/metadata) are orchestrated.
3.  **UI & Screens**: `lib/presentation/screens/`. Most screens are named intuitively (e.g., `player_screen.dart`, `library_screen.dart`).
4.  **Database Schema**: `lib/services/database_service.dart`.
5.  **Search Logic**: `lib/domain/services/search_service.dart`.

## 🛠️ Common Workflows

### Running Tests
Use standard Flutter test command:
```bash
flutter test
```
To run a specific test:
```bash
flutter test test/shuffle_logic_test.dart
```

### Adding a Service
1. Define the service in `lib/services/`.
2. Register a provider for it in `lib/providers/providers.dart` (or a dedicated provider file).
3. Inject it where needed using Riverpod's `ref`.

### Modifying the Shuffle Algorithm
The shuffle algorithm is highly sophisticated and uses "Personalities" (`ShufflePersonality` in `lib/models/shuffle_config.dart`):
- **Default**: Balanced weighting.
- **Explorer**: High randomness, favors least-played songs.
- **Consistent**: Low randomness, favors favorites.
- **Custom**: Granular weights for favorites, suggest-less, etc.

**Key Logic**:
- **Anti-Repeat**: Penalizes songs recently played (up to 95% penalty).
- **Streak Breaker**: Reduces probability for same artist/album repeats.
- **History**: Tracking is done via `HistoryEntry` and stored in `ShuffleState`.

Always run `test/shuffle_logic_test.dart` and `test/personality_logic_test.dart` after modifications.

## Critical Constraints for Agents

- **Offline Only**: Do not add features that require an internet connection unless explicitly requested.
- **File-Based Identity**: User data (stats, favorites) is linked to filenames. Do not change this unless explicitly told to.
- **Provider Decoupling**: Avoid circular dependencies. `AudioPlayerManager` and `UserDataNotifier` are intentionally kept separate; updates should be pushed, not pulled via cross-injection.
- **No git commits**: You are only allowed to use git commands to *READ*, you are *NOT* allowed to make git commits *NOR* other write operations within git.
- **Comments**: Keep comments minimal. Explain *why*, not *what*. Do not talk to yourself during comments. Do not add LLM specific comments such as "// added this line" or "// per user request", do not add too many comments per function, explain function at beginning then fully implement it with no more comments.
- **Emojis**: Do *NOT* *EVER* use emojis in code, code comments or messages.
- **No building**: Do *NOT* *EVER* build the project *UNLESS* explicitly requested.
- **No tests**: Do NOT run flutter analyze nor flutter test unless the user explicitly requests you to do so. Trust your code.

## Established Patterns

- **Initialization**: App initialization logic (cache setup, database init) is in `lib/main.dart`.
- **Platform Specifics**: Check `AndroidManifest.xml` (Android) and `Info.plist` (iOS/macOS) for permissions.
- **Mocking**: Use `mockito` for unit tests. Run `dart run build_runner build` if mocks need regeneration.

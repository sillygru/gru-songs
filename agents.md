# Agent Documentation - Wispie Music Player

## Critical Rules

- **No git commands** - Never run write git operations. Git commands are for reading only.
- **No building** - Do not run `flutter build` or `flutter run` unless explicitly requested
- **No emojis** - Never use emojis in code, comments, or messages
- **Offline only** - Do not add features requiring internet connection unless explicitly requested
- **File-based identity** - User data (favorites, stats) is linked to filenames. Do not change this
- **Comments** - Minimal. Explain _why_, not _what_. No LLM-specific comments like "// added this"

## Architecture Summary

Local-First Flutter music player using Riverpod for state management with MVVM/Repository pattern.

## Documentation Index

Read only the file you need for your task:

| File | When to Read |
|------|--------------|
| [`agents/01-architecture.md`](agents/01-architecture.md) | Understanding overall structure, tech stack, initialization |
| [`agents/02-playback-shuffle.md`](agents/02-playback-shuffle.md) | Modifying playback, queue, or shuffle algorithm |
| [`agents/03-library-state.md`](agents/03-library-state.md) | Adding/removing songs, scanning, bulk metadata operations |
| [`agents/04-data-layer.md`](agents/04-data-layer.md) | Database operations, caching, file management, FFmpeg |
| [`agents/05-models.md`](agents/05-models.md) | Understanding data models (Song, Playlist, ShuffleConfig, etc.) |

## Quick Reference

### Key Files
- **Playback**: `lib/services/audio_player_manager.dart`
- **Library State**: `lib/providers/providers.dart` -> `songsProvider`
- **User Data**: `lib/providers/user_data_provider.dart`
- **Database**: `lib/services/database_service.dart`
- **Search**: `lib/domain/services/search_service.dart`
- **Library Logic**: `lib/services/library_logic.dart`
- **Queue History**: `lib/providers/queue_history_provider.dart`
- **Queue History Screen**: `lib/presentation/screens/queue_history_screen.dart`

### Running Tests
```bash
flutter test
flutter test test/shuffle_logic_test.dart  # Specific test
```

### Project Structure
```
lib/
├── services/      # Primary logic layer
├── providers/     # Riverpod state management
├── models/        # Core entities
├── domain/        # Domain logic (search, etc.)
├── data/          # Data source abstractions
└── presentation/ # UI screens, widgets, routes
    ├── screens/
    ├── widgets/
    └── routes/
```

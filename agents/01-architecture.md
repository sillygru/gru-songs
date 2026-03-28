# Architecture

## Overview

Wispie is a Local-First Flutter music player with offline-only functionality. It uses Riverpod for state management following MVVM/Repository patterns.

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart 3.x) |
| State Management | flutter_riverpod (Notifier, AsyncNotifier, Provider) |
| Audio Engine | just_audio, just_audio_background |
| Database | SQLite via sqflite |
| Metadata | metadata_god, audio_metadata_reader |
| Audio Processing | ffmpeg_kit_flutter_new_min |
| Caching | flutter_cache_manager, custom CacheService |

## Directory Structure

```
lib/
├── main.dart              # App entry point, initialization
├── services/              # Primary business logic layer
│   ├── audio_player_manager.dart
│   ├── database_service.dart
│   ├── cache_service.dart
│   ├── scanner_service.dart
│   └── ...
├── providers/             # Riverpod state management
│   ├── providers.dart     # Core providers (songsProvider, etc.)
│   ├── user_data_provider.dart
│   ├── search_provider.dart
│   ├── theme_provider.dart
│   ├── settings_provider.dart
│   └── ...
├── models/                # Core data entities
│   ├── song.dart
│   ├── shuffle_config.dart
│   ├── playlist.dart
│   ├── mood_tag.dart
│   └── ...
├── domain/                # Domain-specific logic
│   ├── models/
│   └── services/search_service.dart
├── data/                  # Data source abstractions
│   ├── models/
│   └── repositories/
└── presentation/          # UI layer
    ├── screens/
    ├── widgets/
    └── routes/
```

## Initialization Flow

`main.dart` performs parallel initialization:

1. **MetadataGod** - Audio metadata reading
2. **CacheService** - Image and metadata caching
3. **ColorExtractionService** - Palette generation
4. **AudioSession** - System audio configuration
5. **JustAudioBackground** - Background playback

Then:
- Database initialization (with migration from user-specific to single-user DBs)
- Setup state check
- Auth state load
- App widget rendering

## Key Architectural Patterns

### Provider Decoupling
`AudioPlayerManager` and `UserDataNotifier` are intentionally separate. Updates are pushed, not pulled via cross-injection.

### Repository Pattern
Data access abstracted through repositories (e.g., `SongRepository` for lyrics extraction).

### Service Layer
Business logic encapsulated in services under `lib/services/`. Services are registered as providers and injected via Riverpod's `ref`.

## Adding a New Service

1. Create service class in `lib/services/`
2. Register provider in `lib/providers/providers.dart` (or dedicated provider file)
3. Inject via `ref.read()` or `ref.watch()` where needed

## Key Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `songsProvider` | AsyncNotifier | Song library state |
| `userDataProvider` | Notifier | User data (favorites, hidden, playlists) |
| `searchProvider` | Notifier | Search state and results |
| `selectionProvider` | Notifier | Multi-select for bulk operations |
| `indexerProvider` | Notifier | Library scanning state |
| `themeProvider` | Notifier | App theming |
| `settingsProvider` | Notifier | App settings |

## Platform Configuration

- **Android**: `android/app/src/main/AndroidManifest.xml` for permissions
- **iOS**: `ios/Runner/Info.plist` for permissions

# Agent Documentation - Wispie Music Player

## Critical Rules

- **No git commands** - Never run write git operations. Git commands are for reading only.
- **No building** - Do not run `flutter build` or `flutter run` unless explicitly requested
- **No emojis** - Never use emojis in code, comments, or messages
- **Offline only** - Do not add features requiring internet connection unless explicitly requested
- **File-based identity** - User data (favorites, stats) is linked to filenames. Do not change this
- **Comments** - Minimal. Explain _why_, not _what_. No LLM-specific comments like "// added this"
- **Always run `dart format .` after all changes are done, and verify `flutter analyze --no-pub` passes with no issues before finishing**

## Code & Architecture Standards

Do not generate "vibe-coded" logic. Follow these rules:

- **Explicit error handling** - Catch specific exceptions. No broad `try/catch` that silences errors. No happy-path assumptions.
- **Modular structure** - Break monolithic widgets and functions into small, testable units. If a `build` method exceeds 50 lines, extract stateless widgets.
- **Strong typing** - No force unwrap (`!`). No `dynamic`. Leverage Dart's null safety properly.
- **No magic values** - No blind timeouts or arbitrary sleeps. Use proper state synchronization.
- **Riverpod everywhere** - Do not use `StatefulWidget` + `setState` for global state. Use the existing Riverpod providers.

Before writing code, reason through: side effects, failure modes, security, and reversibility.

## Architecture Summary

Local-First Flutter music player using Riverpod for state management with MVVM/Repository pattern.

### Directory layering (mid-migration)

Two generations coexist: legacy (`lib/models/`, `lib/services/`, `lib/providers/`, `lib/theme/`) and newer (`lib/data/`, `lib/domain/`, `lib/presentation/`). Prefer newer for new code. Don't bulk-relocate existing files as a side effect of unrelated work.

### `filename` is the primary key for all user data

Every user-data table (`favorite`, `suggestless`, `hidden`, `playlist_song`, `merged_song`, `song_mood`, `recommendation_*`) keys on the song's **filename**, not a path or synthetic id. Renaming a file outside the app orphans its stats. Merged songs map several filenames to one group id (see `AudioPlayerManager._getMergedSiblings`).

### Databases

`DatabaseService` (`lib/services/database_service.dart`, singleton via `.instance`) owns two SQLite files: `wispie_stats.db` (play sessions/events) and `wispie_data.db` (library, playlists, favorites, merged groups, mood tags, queue snapshots). Schema is declared in create-time strings *and* canonical maps (`userDataTableSql`, `userDataExpectedColumns`, `userDataIndexSql`) — both must stay in sync.

### Playback

`AudioPlayerManager` wraps `just_audio` + `just_audio_background`, owns queue/shuffle/crossfade/volume/stats. Hot-path state exposed via `ValueNotifier`s (not Riverpod) for narrow UI rebuilds. Queue mutations serialize through `_queueMutationChain`.

### Shuffle

`lib/domain/services/shuffle_weight_service.dart` — pure `calculateWeight(...)` with personalities (`consistent`, `explorer`, `custom`, etc.) as multiplicative penalties/boosts. Tested directly in `test/shuffle_logic_test.dart`, `test/shuffle_weight_distribution_test.dart`, `test/personality_logic_test.dart`.

### State management

Riverpod 3 with `Notifier`/`AsyncNotifier` API. `lib/providers/providers.dart` is the hub. Derived data should be a `Provider` over `songsProvider` + `userDataProvider`, not a duplicated cache.

### Library scanning

`ScannerService` runs in isolates, lazy: fast scan writes minimal rows, then metadata enrichment and cover extraction in throttled batches. Video thumbnails go through `FFmpegService` (platform channels, main thread only).

### Search

`SearchService` (domain) over `SearchIndexRepository` (data), indexing title/artist/album/lyrics for prefix search with filter chips.

### UI system

`lib/presentation/tokens/player_tokens.dart` is the source of truth for spacing, radii, motion durations and curves; `app_tokens.dart` aliases them. `UnifiedPlayerScreen` is a shell around three panes (lyrics / now-playing / queue) — keep chrome out of the panes.

### Testing

DB-, prefs- or path-touching tests must use `TestEnvironment` from `test/test_helpers.dart` (`setUpAll`/`tearDownAll`). It creates a temp documents directory, swaps in `databaseFactoryFfi`, and mocks path_provider, SharedPreferences and the `gru_songs/volume` channels.

## UI / Design Standard

Do not generate "vibe-coded" UI.

- **Vibrant color blocking** - Use intentional, high-contrast solid colors in large blocks. Define a strict palette.
- **No gradients** - Forbidden in UI elements, backgrounds, and text.
- **No borders or outlines** - Do not use `border`, `ring`, or outlines to separate elements. Use color blocking, whitespace, and layout geometry instead.
- **Smooth animations** - Use subtle, deliberate transitions (`cubic-bezier(0.4, 0, 0.2, 1)`) for state changes.
- **Design tokens first** - Never hardcode hex values or pixel sizes. Reference a theme provider or token system.
- **Consistent component hierarchy** - Use a predictable grid/flexbox layout. No absolute positioning unless mathematically necessary.
- **Semantic accessibility** - Use semantic Flutter widgets (`ListTile`, `IconButton`, etc.), manage focus states, and ensure proper labeling.

Before returning UI code, verify: no gradients, no borders used for separation, all styling references design tokens, animations are deliberate.

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

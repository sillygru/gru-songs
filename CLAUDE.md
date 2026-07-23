# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Wispie is a local-library music player written in Flutter, targeting Android and iOS. There is no backend and no account — the library itself is entirely local, and every feature reads from the device filesystem and two local SQLite databases.

"Local" describes the library, not the process: a few features do reach the network, each of them optional and none of them required for playback. Today those are the GitHub release check (`update_service.dart`), telemetry (`telemetry_service.dart`, inert without a compiled-in secret) and online lyrics lookup against LRCLIB (`lrclib_service.dart`). All three use `dart:io HttpClient` directly rather than adding an HTTP package. Nothing about the library — songs, covers, stats, playlists — is ever uploaded.

## Boundaries

- **Never run `flutter run` or `flutter build`.** Verification stays within `flutter analyze` and `flutter test`. If a change genuinely needs a running app or a built artifact, ask the user to run it.
- **Never run git write commands** (`commit`, `push`, `merge`, `rebase`, `reset`, `checkout -b`, `stash`, tag/branch mutations) unless the user explicitly asks. Read-only git (`status`, `diff`, `log`, `show`) is fine.

## Commands

```bash
flutter pub get

flutter test                                   # full suite (36 files under test/)
flutter test test/shuffle_logic_test.dart      # single file
flutter test --plain-name "substring of name"  # single test / group

flutter analyze                    # CI gate
dart format --set-exit-if-changed .  # CI gate — CI fails on unformatted code
```

CI (`.github/workflows/flutter_tests.yml`) pins Flutter **3.44.2** and runs `analyze` → `test`; formatting is checked before analysis.

Release builds are run by the user or CI, not by Claude — for reference they are `flutter build apk --release --target-platform=android-arm64` (and `android-arm` for ARMv7).

`--dart-define=TELEMETRY_SECRET=...` is what enables telemetry (`String.fromEnvironment` in `lib/services/telemetry_service.dart`). Local and community builds compile with an empty secret and send nothing; don't add code paths that assume telemetry is live.

## Architecture

### Directory layering is mid-migration

Two generations of structure coexist and both are live:

- Legacy: `lib/models/`, `lib/services/`, `lib/providers/`, `lib/theme/`
- Newer: `lib/data/` (repositories, persistence models), `lib/domain/` (pure logic + services), `lib/presentation/` (screens, widgets, components, dialogs, tokens)

Prefer the newer layering for new code — pure, testable logic in `domain/`, I/O in `data/` or `services/`, everything visual under `presentation/`. Don't bulk-relocate existing files as a side effect of unrelated work.

### `filename` is the primary key for all user data

Every user-data table (`favorite`, `suggestless`, `hidden`, `playlist_song`, `merged_song`, `song_mood`, `recommendation_*`) keys on the song's **filename**, not a path or a synthetic id. This is the single most load-bearing invariant in the codebase:

- Renaming a file outside the app orphans its stats, favorites and shuffle weights (documented user-facing caveat in the README).
- Any in-app rename or metadata-write flow must migrate the dependent rows, or data is silently lost.
- Merged songs map several filenames to one group id; playback/shuffle code frequently resolves "merged siblings" before acting on a filename (see `AudioPlayerManager._getMergedSiblings`).

### Databases

`DatabaseService` (`lib/services/database_service.dart`, ~3k lines, singleton via `.instance`) owns two SQLite files in the app documents directory:

- `wispie_stats.db` — `playsession`, `playevent`
- `wispie_data.db` — library (`song`), playlists, favorites, merged groups, mood tags, queue snapshots

`init()` returns `true` when it migrated from the older per-username `${username}_data.db` layout; `main.dart` re-runs `runApp` in that case.

Schema is declared in more than one place on purpose — the create-time schema strings *and* the canonical maps `userDataTableSql`, `userDataExpectedColumns`, `userDataIndexSql`. Those maps drive backup import, granular restore and schema repair. **Adding or changing a table/column means updating both**, otherwise restores from backup silently produce a broken DB.

### Playback

`AudioPlayerManager` (`lib/services/audio_player_manager.dart`) wraps `just_audio` + `just_audio_background` and is the single owner of the queue, shuffle state, crossfade/gap transitions, volume fading, stats emission and playback-state persistence. It is exposed through `audioPlayerManagerProvider` but publishes hot-path state (current song, playing, queue, shuffle) via `ValueNotifier`s rather than Riverpod state, so playback UI rebuilds narrowly. Follow that pattern rather than lifting playback state into providers.

Queue mutations are serialized through a `_queueMutationChain` future — new mutation entry points must join that chain.

### Shuffle

`lib/domain/services/shuffle_weight_service.dart` exposes a single pure `calculateWeight(...)`. Personalities (`consistent`, `explorer`, `custom`, …) are configured by `ShuffleConfig` and applied as multiplicative penalties/boosts from history position, play count, favorites, "suggest less", and skip statistics. It is pure so it can be tested directly — `test/shuffle_logic_test.dart`, `test/shuffle_weight_distribution_test.dart`, `test/personality_logic_test.dart` do exactly that. Keep it free of I/O.

### State management

Riverpod 3 with the `Notifier`/`AsyncNotifier` API. `lib/providers/providers.dart` is the hub (service providers, `songsProvider`, derived `playCountsProvider` / `recommendationsProvider` / artist & album lists); `user_data_provider.dart` holds favorites/playlists/hidden/merged state. Derived data should be a `Provider` over `songsProvider` + `userDataProvider`, not a duplicated cache.

### Library scanning

`ScannerService` runs scans in isolates (`_ScanParams` / `_RebuildParams`) and is deliberately lazy: a fast scan writes minimal song rows, then metadata enrichment and cover extraction happen in throttled batches or on first view. Video thumbnails go through `FFmpegService`, which uses platform channels and therefore must run on the main thread after the isolate work.

### Search

`SearchService` (domain) over `SearchIndexRepository` (data), indexing title/artist/album/lyrics for fast prefix search with filter chips.

### UI system

`lib/presentation/tokens/player_tokens.dart` is the source of truth for spacing, radii, motion durations and curves; `app_tokens.dart` deliberately *aliases* those values so the player and the rest of the app can't drift. Use the tokens — don't hardcode paddings, radii or animation durations.

`UnifiedPlayerScreen` is a shell owning all chrome (cover backdrop, header, segmented pill, transport dock) around three panes — lyrics / now-playing / queue — which render content only. Keep chrome out of the panes.

## Testing

DB-, prefs- or path-touching tests must use `TestEnvironment` from `test/test_helpers.dart` in `setUpAll`/`tearDownAll`. It creates a temp documents directory, swaps in `databaseFactoryFfi`, and mocks path_provider, SharedPreferences and the `gru_songs/volume` channels. Without it, tests write real databases into the developer's Documents folder.

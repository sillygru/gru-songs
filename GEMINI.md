# Project Instructions: Gru Songs (Flutter)

## ⛔️ Constraints
- **NEVER COMMIT OR PUSH WITHOUT PERMISSION:** Never commit or push any code (git commit, git push, etc.) unless you have explicit permission for the specific task.
- **NON-SERVER ENVIRONMENT:** You are running in a CLI environment, not the production server. Avoid absolute paths (e.g., `/home/...`) and do not rely on `.env` values during testing. Use relative paths or mock settings to ensure portability. If the error is because of /home/sillygru its because its trying to use the server envinronment inside the .env

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel. Features user authentication, session-based statistics, favorites, and a "suggest less" recommendation filter.
**Now features comprehensive offline capabilities** with "Stream & Cache" architecture.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **State Management:** `flutter_riverpod` (Riverpod 3.x) - Decoupled MVVM architecture.
- **Data Modeling:** `equatable`, `uuid`
- **Audio Engine:** `just_audio`, `rxdart` (for stream combining)
- **Caching & Offline:** Custom V3 `CacheService` (using `getApplicationSupportDirectory`), `crypto`, `path`
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **UI Components:** `audio_video_progress_bar`, `GruImage` (custom cache-first widget)
- **Networking:** `http` with custom `HttpOverrides` for TLS/SSL handshake stability.
- **Backend:** FastAPI (Python 3.10+) utilizing lifespan handlers for robust startup/shutdown logic.
- **Backup & Notifications:** Automated backups of user data with MD5-based change detection. Discord bot integration for logs and admin commands.

## 🌐 Networking & API
- **Base URL:** `https://[REDACTED]/music`
  - **Endpoints:**
  - **Music:**
    - `GET /list-songs` (includes `play_count` and `mtime` if available)
    - `GET /sync-check` (Returns MD5 hashes for songs, favorites, shuffle state, etc.)
    - `GET /cover/{filename}` (Cache-Control: 1 year)
    - `GET /lyrics/{filename}` (.lrc files)
    - `GET /lyrics-embedded/{filename}` (Cache-Control: 1 year)
  - **Auth:**
    - `POST /auth/signup`
    - `POST /auth/login`
    - `POST /auth/update-password`
    - `POST /auth/update-username`
  - **User Data & Stats:**
    - `GET/POST /user/favorites`, `DELETE /user/favorites/{filename}`
    - `GET/POST /user/suggest-less`, `DELETE /user/suggest-less/{filename}`
    - `GET /user/shuffle` (Gets persistent shuffle settings, history, and personality)
    - `POST /user/shuffle` (Updates persistent shuffle settings, history, and personality)
    - `GET /stats/summary` (Aggregated user statistics)
    - `POST /stats/track` (Tracks individual play events)
    - `GET /stats/fun` (Retrieves fun/interesting statistics)
    - `GET /user/db/{db_type}` (Downloads user database files: `stats`, `data`, `final_stats`)
    - `POST /user/db/{db_type}` (Uploads user database files: `stats`, `data`, `final_stats`)

### ⚠️ Critical Handshake Fix
The app employs a custom `HttpOverrides` class in `main.dart` and a custom `IOClient` (initialized with a `HttpClient` that accepts bad certificates) in `api_service.dart`. **These are crucial and must not be removed.** They are essential to prevent `HandshakeException` when establishing connections to the Tailscale Funnel URL from mobile devices, ensuring stable network communication.

## 📱 Platform Specifics

### Desktop & iPad
- **UI:** Includes a dedicated volume slider in the `NowPlayingBar` and `PlayerScreen`.

### Android
- **Permissions:** `INTERNET`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`.
- **Manifest:** `android:usesCleartextTraffic="true"` is enabled.
- **Activity:** Uses `com.ryanheise.audioservice.AudioServiceActivity`.

### iOS
- **Permissions:** `UIBackgroundModes` includes `audio`.
- **ATS:** `NSAppTransportSecurity` allows arbitrary loads for streaming.

## 🏗 Architecture & Best Practices
- **Frontend:** Modular **MVVM/Clean Architecture**.
  - **Provider Decoupling:** `AudioPlayerManager` and `UserDataNotifier` are decoupled to prevent `CircularDependencyError`. `UserDataNotifier` proactively pushes updates to the manager.
  - **Caching Strategy (V2):**
    - **Instant Cache-First:** Always serve from local storage immediately if the file exists.
    - **Background Validation:** After serving from cache, perform an async check of the asset's version (`mtime` or hash). If changed, download and atomically replace the cached file.
    - **Atomic Replacement:** Downloads are written to `.tmp` files and renamed upon completion to prevent corruption.
    - **Lazy Pre-caching:** Only the current song and the next 2 songs in the queue are pre-cached.
  - **Images:** Handled by `GruImage` widget which uses the V2 `CacheService`. Features a built-in loading spinner and error handling.
  - **Sync Indicator:** Visual status bar at the top of the screen (Offline, Syncing, Using Cache).
  - **Pull-to-Refresh:** Available on main data screens. Triggers background sync for songs, favorites, and **shuffle personality/history**.
  - **Playback Resume:** Position is only resumed for the specific song that was last playing when the app closed. New song selections always start at position 0.
  - **Queue Management:** 
    - **Shuffle Toggle:** Capture current player state to **preserve the position** of the currently playing song during re-shuffling.
    - **Shuffle Logic:** Employs a weighted random selection algorithm with multiple **Personalities** (Default, Explorer, Consistent).
      - **Anti-repeat:** History-based probability reduction (up to 95%).
      - **Streak Breaker:** Reduced probability for same artist/album streaks.
      - **Persistence:** Personality, configuration, and history are stored server-side and synchronized bidirectionally.
- **Backend:** 
  - **Persistence:**
    - `users/<username>_data.db`: Profile, favorites, and suggest-less.
    - `users/<username>_stats.db`: Session history and raw play events.
    - `users/<username>_final_stats.json`: Aggregated summary and persistent shuffle state (including personality). These files are mirrored between the client and server.
  - **Backup Service:** 
    - Runs in a background thread every 6 hours.
    - **Optimization:** Calculates an MD5 hash of the `users/` directory (filenames, sizes, mtimes). **Skips backup generation** if no changes are detected.
    - Persists hash state in `backup_state.json`.
    - Logs skips and completions to Discord.
  - **Discord Bot:**
    - `!backup [true/false]`: Manually trigger backup (optional timer reset).
    - `!stats [username]`: View rich statistics embed for a user.

## 📂 Project Structure
### Frontend (`lib/`)
- `models/`: Data structures (`song.dart`, `queue_item.dart`, `shuffle_config.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers (`auth_provider.dart`, `user_data_provider.dart`, `providers.dart`).
- `services/`: Core logic (`api_service.dart`, `audio_player_manager.dart`, `cache_service.dart`, `storage_service.dart`, `stats_service.dart`).
- `presentation/`:
  - `screens/`: `AuthScreen`, `HomeScreen`, `MainScreen`, `PlayerScreen`, `SearchScreen`, `LibraryScreen`, `ProfileScreen`, `CacheManagementScreen`.
  - `widgets/`: `NowPlayingBar`, `SongOptionsMenu`, `GruImage`, `NextUpSheet`.

### Backend (`server/`)
- `main.py`: Routes and bot management.
- `user_service.py`: Core logic for auth, stats, and bidirectional sync.
- `backup_service.py`: Optimized scheduler with change-detection hashing.
- `queue_service.py`: Server-side shuffle and queue generation.

## 📦 Build Commands

### Android
```bash
flutter build apk --release
```

### iOS (Xcode)
```bash
flutter build ios --release
open ios/Runner.xcworkspace
```

## 🏷️ Versioning

- **Format:** `Major.Normal.Bugfix` (e.g., `5.1.3`).

- **Automatic Update:** When the user requests to update the version, search (e.g., with `grep -r "Current Version"` excluding the `.git` directory) for all places in the codebase where `"Current Version"` appears. Update each instance to reflect the new version number. This ensures all references are synchronized automatically.

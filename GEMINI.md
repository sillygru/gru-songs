# Project Instructions: Gru Songs (Flutter)

## ⛔️ Constraints
- **NO GIT COMMANDS:** Do not ever run git commands (git add, commit, push, etc.) unless explicitly authorized for a specific task.
- **NON-SERVER ENVIRONMENT:** You are running in a CLI environment, not the production server. Avoid absolute paths (e.g., `/home/...`) and do not rely on `.env` values during testing. Use relative paths or mock settings to ensure portability. If the error is because of /home/sillygru its because its trying to use the server envinronment inside the .env

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel. Features user authentication, session-based statistics, playlists with added-date tracking, favorites, and a "suggest less" recommendation filter.
**Now features comprehensive offline capabilities** with "Stream & Cache" architecture.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **State Management:** `flutter_riverpod` (Riverpod 3.x) - Decoupled MVVM architecture.
- **Data Modeling:** `equatable`, `uuid`
- **Audio Engine:** `just_audio`, `rxdart` (for stream combining)
- **Caching & Offline:** Custom V2 `CacheService` (using `getApplicationSupportDirectory`), `crypto`, `path`
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
    - `GET /sync-check` (Returns MD5 hashes for songs, favorites, playlists, shuffle state, etc.)
    - `GET /stream/{filename}`
    - `GET /cover/{filename}` (Cache-Control: 1 year)
    - `GET /lyrics/{filename}` (.lrc files)
    - `GET /lyrics-embedded/{filename}` (Cache-Control: 1 year)
    - `POST /music/upload` (Upload local audio files)
    - `POST /music/yt-dlp` (Download audio from YouTube)
  - **Auth:**
    - `POST /auth/signup`
    - `POST /auth/login`
    - `POST /auth/update-password`
    - `POST /auth/update-username`
  - **User Data:**
    - `GET/POST /user/favorites`, `DELETE /user/favorites/{filename}`
    - `GET/POST /user/playlists`, `DELETE /user/playlists/{playlist_id}`
    - `POST /user/playlists/{playlist_id}/songs`, `DELETE /user/playlists/{playlist_id}/songs/{filename}`
    - `GET/POST /user/suggest-less`, `DELETE /user/suggest-less/{filename}`
    - `GET/POST /user/shuffle` (Persistence for settings, history, and personality)
    - `POST /stats/track`

### ⚠️ Critical Handshake Fix
The app uses a custom `HttpOverrides` class in `main.dart` and a custom `IOClient` in `api_service.dart`. **Do not remove these.** They are required to prevent `HandshakeException` when connecting to the Tailscale Funnel URL from mobile devices.

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
  - **Pull-to-Refresh:** Available on main data screens. Triggers background sync for songs, favorites, playlists, and **shuffle personality/history**.
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
    - `users/<username>_playlists.db`: Detailed playlist data with `added_at` timestamps.
    - `users/<username>_stats.db`: Session history and raw play events.
    - `users/<username>_final_stats.json`: Aggregated summary and persistent shuffle state (including personality).
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
- `models/`: Data structures (`song.dart`, `playlist.dart`, `queue_item.dart`, `shuffle_config.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers (`auth_provider.dart`, `user_data_provider.dart`, `providers.dart`).
- `services/`: Core logic (`api_service.dart`, `audio_player_manager.dart`, `cache_service.dart`, `storage_service.dart`, `stats_service.dart`).
- `presentation/`:
  - `screens/`: `AuthScreen`, `HomeScreen`, `MainScreen`, `PlayerScreen`, `PlaylistsScreen`, `SearchScreen`, `LibraryScreen`, `ProfileScreen`, `CacheManagementScreen`.
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
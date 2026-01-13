# Project Instructions: Gru Songs (Flutter)

## ⛔️ Constraints
- **NO GIT COMMANDS:** Do not ever run git commands (git add, commit, push, etc.).

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel. Features user authentication, session-based statistics, playlists with added-date tracking, favorites, and a "suggest less" recommendation filter.
**Now features comprehensive offline capabilities** with "Stream & Cache" architecture.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **State Management:** `flutter_riverpod` (Riverpod 3.x)
- **Data Modeling:** `equatable`, `uuid`
- **Audio Engine:** `just_audio`, `rxdart` (for stream combining)
- **Caching & Offline:** Custom V2 `CacheService` (using `getApplicationSupportDirectory`), `crypto`, `path`
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **UI Components:** `audio_video_progress_bar`, `GruImage` (custom cache-first widget)
- **Networking:** `http` with custom `HttpOverrides` for TLS/SSL handshake stability.
- **Backend:** FastAPI (Python 3.10+) utilizing lifespan handlers for robust startup/shutdown logic.

## 🌐 Networking & API
- **Base URL:** `https://[REDACTED]/music`
  - **Endpoints:**
  - **Music:**
    - `GET /list-songs` (includes `play_count` and `mtime` if available)
    - `GET /sync-check` (Returns MD5 hashes for songs, favorites, playlists, etc.)
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
    - `GET/POST /user/shuffle` (Persistence for settings and history)
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
  - **Caching Strategy (V2):**
    - **Instant Cache-First:** Always serve from local storage immediately if the file exists.
    - **Background Validation:** After serving from cache, perform an async check of the asset's version (`mtime` or hash). If changed, download and atomically replace the cached file.
    - **Atomic Replacement:** Downloads are written to `.tmp` files and renamed upon completion to prevent corruption. If a file is locked (during playback), an alternative path is used and metadata is updated.
    - **Lazy Pre-caching:** Aggressive background downloading is disabled. Only the current song and the next 2 songs in the queue are pre-cached.
    - **Metadata Reclamation:** If a file exists on disk but is missing from metadata (e.g., after an app update), the service automatically re-registers it.
    - **Download Mutex:** Prevents duplicate parallel downloads for the same asset.
    - **Pause Mechanism:** Clearing the cache triggers a 10-second pause for all background operations to prevent immediate re-caching.
    - **Storage Cleanup:** Legacy `flutter_cache_manager` data is automatically cleaned up in the background on the first run of V2.
  - **Images:** Handled by `GruImage` widget which uses the V2 `CacheService`.
  - **Sync Indicator:** Visual status bar at the top of the screen (Offline, Syncing, Using Cache).
  - **Pull-to-Refresh:** Available on all main data screens to force a background sync check.
  - **UI Gestures:** Swipe-up on album cover in `PlayerScreen` to reveal synchronized lyrics.
  - **Context Menus:** Unified long-press options menu for songs (Favorite, Add to Playlist, Suggest Less, Play Next).
  - **Visual Cues:** Play counts displayed in white circle bubbles; suggest-less songs are greyed out with a line-through.
  - **Queue Management:** 
    - **Next Up List:** Drag-and-drop reordering, swipe-to-remove.
    - **Priority System:** "Play Next" inserts songs into a priority block that overrides shuffle. 
    - **Shuffle Logic:** Employs a weighted random selection algorithm.
      - **Anti-repeat:** Recent history receives a probability reduction (up to 95%) that decays as the song moves further back in the history.
      - **Streak Breaker:** Reduced probability for songs from the same artist or album as the last played track.
      - **User Preferences:** Favorites receive a +15% weight boost; suggest-less songs receive an 80% reduction.
      - **Metadata Safety:** Missing artist or album data skips relevant rules without affecting selection.
      - **Persistence:** Configuration and history are stored locally and synchronized with the backend.
    - **Recommendation Engine:** Aligned with shuffle philosophy. Employs a scoring system where favorites are boosted (+5.0 points) and suggest-less songs are heavily penalized (-10.0 points) rather than hidden, ensuring all music remains accessible based on play count and variety.
- **Backend:** 
  - **Persistence:** 
    - `users/<username>_data.db`: Profile, favorites, and suggest-less.
    - `users/<username>_playlists.db`: Detailed playlist data with `added_at` timestamps.
    - `users/<username>_stats.db`: Session history and raw play events.
    - `users/<username>_final_stats.json`: Aggregated summary and persistent shuffle state.
    - `users/uploads.db`: Global record of song uploads and their owners.
    - `songs/downloaded/`: Subdirectory for uploaded or yt-dlp downloaded songs.
  - **Stats Engine:** Rounding precision to 2 decimal places. Play counts filter for ratio > 0.25 across all non-favorite event types. Shuffle history automatically updates upon song completion.

## 📂 Project Structure
### Frontend (`lib/`)
- `models/`: Data structures (`song.dart`, `playlist.dart`, `queue_item.dart`, `shuffle_config.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers (`auth_provider.dart`, `user_data_provider.dart`).
- `services/`: Core logic (`api_service.dart`, `audio_player_manager.dart`, `cache_service.dart`, `storage_service.dart`, `stats_service.dart`).
- `presentation/`:
  - `screens/`: `AuthScreen`, `HomeScreen`, `MainScreen`, `PlayerScreen`, `PlaylistsScreen`, `SearchScreen`, `LibraryScreen`, `ProfileScreen`.
  - `widgets/`: `NowPlayingBar`, `SongOptionsMenu`, `GruImage`, `NextUpSheet`.
- `main.dart`: Entry point.

### Backend (`server/`)
- `main.py`: Routes and background tasks.
- `user_service.py`: Core logic for auth, stats (buffer), and user data.
- `models.py`: Pydantic models.
- `services.py`: Music metadata extraction.
- `settings.py`: Configuration.
- `users/`: JSON storage for user data.
## 📦 Build Commands

### Android
```bash
# Debug (installs on emulator)
flutter build apk --debug

# Release (Standard APK)
flutter build apk --release

# Release (App Bundle for Play Store)
flutter build appbundle
```

### iOS (Xcode)
```bash
# 1. Build the iOS project (prepares files for Xcode)
flutter build ios --release

# 2. Open the project in Xcode to manage signing and deployment
open ios/Runner.xcworkspace

# 3. Build a distribution package (IPA)
flutter build ipa --release
```
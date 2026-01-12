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
- **Caching & Offline:** `flutter_cache_manager`, `path_provider` (Stale-while-revalidate strategy)
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **UI Components:** `audio_video_progress_bar`, `cached_network_image`
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
  - **Caching Strategy:**
    - **Hash-Based Sync:** "Cache-First". Loads instantly from local storage. In the background, compares local MD5 hashes with `/sync-check` response. Only fetches fresh data if hashes mismatch.
    - **Metadata:** Loads instantly from local JSON (via `StorageService`), updates from API in background via sync.
    - **Audio:** "Stream & Cache". Checks `flutter_cache_manager` for local file first. If missing, streams URL and downloads in background. Current song is verified in background upon playback start.
    - **Images/Lyrics:** HTTP Cache headers (1 year immutable) + `cached_network_image`.
  - **Sync Indicator:** Visual status bar at the top of the screen (Offline, Syncing, Using Cache).
  - **Pull-to-Refresh:** Available on all main data screens to force a background sync check.
  - **UI Gestures:** Swipe-up on album cover in `PlayerScreen` to reveal synchronized lyrics.
  - **Context Menus:** Unified long-press options menu for songs (Favorite, Add to Playlist, Suggest Less).
  - **Visual Cues:** Play counts displayed in white circle bubbles; suggest-less songs are greyed out with a line-through.
- **Backend:** 
  - **Persistence:** 
    - `users/<username>.json`: Profile and favorites.
    - `users/<username>_playlists.json`: Detailed playlist data with `added_at` timestamps.
    - `users/<username>_stats.json`: Session history.
    - `users/uploads.json`: Global record of song uploads and their owners.
    - `songs/downloaded/`: Subdirectory for uploaded or yt-dlp downloaded songs.
  - **Stats Engine:** Rounding precision to 2 decimal places. Play counts filter for ratio > 0.25 across all non-favorite event types.

## 📂 Project Structure
### Frontend (`lib/`)
- `models/`: Data structures (`song.dart`, `playlist.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers (`auth_provider.dart`, `user_data_provider.dart`).
- `services/`: Core logic (`api_service.dart`, `audio_player_manager.dart`, `storage_service.dart`, `stats_service.dart`).
- `presentation/`:
  - `screens/`: `AuthScreen`, `HomeScreen`, `MainScreen`, `PlayerScreen`, `PlaylistsScreen`, `SearchScreen`, `LibraryScreen`, `ProfileScreen`.
  - `widgets/`: `NowPlayingBar`, `SongOptionsMenu`.
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

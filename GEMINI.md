# Project Instructions: Gru Songs (Flutter)

## ⛔️ Constraints
- **NO GIT COMMANDS:** Do not ever run git commands (git add, commit, push, etc.).

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel. Features user authentication, session-based statistics, playlists, and favorites.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **State Management:** `flutter_riverpod` (Riverpod 3.x)
- **Data Modeling:** `equatable`, `uuid`
- **Audio Engine:** `just_audio`
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **Networking:** `http` with custom `HttpOverrides` for TLS/SSL handshake stability.
- **Backend:** FastAPI (Python 3.10+)

## 🌐 Networking & API
- **Base URL:** `https://[REDACTED]/music`
- **Endpoints:**
  - **Music:**
    - `GET /list-songs`
    - `GET /stream/{filename}`
    - `GET /cover/{filename}`
    - `GET /lyrics/{filename}`
  - **Auth:**
    - `POST /auth/signup`
    - `POST /auth/login`
    - `POST /auth/update-password`
    - `POST /auth/update-username`
  - **User Data:**
    - `GET/POST /user/favorites`
    - `GET/POST /user/playlists`
    - `POST /stats/track`

### ⚠️ Critical Handshake Fix
The app uses a custom `HttpOverrides` class in `main.dart` and a custom `IOClient` in `api_service.dart`. **Do not remove these.** They are required to prevent `HandshakeException` when connecting to the Tailscale Funnel URL from mobile devices.

## 📱 Platform Specifics

### Android
- **Permissions:** `INTERNET`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`.
- **Manifest:** `android:usesCleartextTraffic="true"` is enabled.
- **Activity:** Uses `com.ryanheise.audioservice.AudioServiceActivity`.

### iOS
- **Permissions:** `UIBackgroundModes` includes `audio`.
- **ATS:** `NSAppTransportSecurity` allows arbitrary loads for streaming.

## 🏗 Architecture & Best Practices
- **Frontend:** Follows a modular **MVVM/Clean Architecture** pattern.
  - **Services:** `AuthService`, `StatsService` (Session ID mgmt), `UserDataService`.
  - **Providers:** `authProvider`, `userDataProvider` (Favorites/Playlists), `audioPlayerManagerProvider`.
- **Backend:** Modularized for maintainability.
  - **Stats Engine:** RAM-buffered statistics (flushed every 5m) with session grouping and "active listening" ratio calculation.
  - **User Service:** Handles auth, file-based persistence (JSON), and playlists.

## 📂 Project Structure
### Frontend (`lib/`)
- `models/`: Data structures (`song.dart`, `playlist.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers.
- `services/`: Core logic (`auth_service.dart`, `stats_service.dart`).
- `presentation/`:
  - `screens/`: `AuthScreen`, `HomeScreen`, `SettingsScreen`, `PlaylistsScreen`.
  - `widgets/`: `NowPlayingBar`.
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
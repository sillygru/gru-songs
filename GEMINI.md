# Project Instructions: Gru Songs (Flutter)

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **State Management:** `flutter_riverpod` (Riverpod 3.x)
- **Data Modeling:** `equatable`
- **Audio Engine:** `just_audio`
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **Networking:** `http` with custom `HttpOverrides` for TLS/SSL handshake stability.
- **Backend:** FastAPI (Python 3.10+)

## 🌐 Networking & API
- **Base URL:** `https://[REDACTED]/music`
- **Endpoints:**
  - `GET /list-songs`: Returns JSON list.
  - `GET /stream/{filename}`: Audio stream.
  - `GET /cover/{filename}`: Album art extraction from metadata.
  - `GET /lyrics/{filename}`: `.lrc` file or embedded lyrics.

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
  - **Data Layer:** Repositories handle data fetching and abstraction.
  - **State Layer:** Riverpod providers manage application state and dependency injection.
  - **Presentation Layer:** Separated into `screens` (pages) and `widgets` (reusable components).
- **Backend:** Modularized for maintainability.
  - **Settings:** Environment-based configuration via `.env`.
  - **Services:** Business logic (metadata extraction, file scanning) isolated from routes.

## 📂 Project Structure
### Frontend (`lib/`)
- `models/`: Data structures (e.g., `song.dart`).
- `data/repositories/`: Data access abstraction.
- `providers/`: Riverpod providers for state and services.
- `services/`: Core logic (API client, Audio player lifecycle).
- `presentation/`:
  - `screens/`: UI pages (Home, Player).
  - `widgets/`: Reusable UI components.
- `main.dart`: App entry point and global initializations.

### Backend (`server/`)
- `main.py`: FastAPI routes and application entry point.
- `settings.py`: Configuration management using `python-dotenv`.
- `services.py`: Music processing and metadata logic.
- `.env`: Local environment variables (not committed).
- `requirements.txt`: Python dependencies.

## 📦 Build Commands

### Android
```bash
# Debug (installs on emulator)
flutter build apk --debug

# Release
flutter build apk --release
```

### iOS (Manual IPA)
```bash
# Build the bundle
flutter build ios --release --no-codesign
```

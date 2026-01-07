# Project Instructions: Gru Songs (Flutter)

## 🚀 Overview
A high-performance music streaming app built with Flutter, connecting to a private FastAPI backend hosted behind a Tailscale Funnel.

## 🛠 Tech Stack
- **Frontend:** Flutter (Material 3)
- **Audio Engine:** `just_audio`
- **Background Playback:** `just_audio_background`
- **Audio Session:** `audio_session` (configured for music)
- **Networking:** `http` with custom `HttpOverrides` for TLS/SSL handshake stability.

## 🌐 Networking & API
- **Base URL:** `https://[REDACTED]/music`
- **Endpoints:**
  - `GET /list-songs`: Returns JSON list.
  - `GET /stream/{filename}`: Audio stream.
  - `GET /cover/{filename}`: Album art extraction from metadata.
  - `GET /lyrics/{filename}`: `.lrc` file access.

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
- **Sideloading:** Build with `--no-codesign` and package manually into a `Payload` folder to create a `.ipa`.

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
# 1. Build the bundle
flutter build ios --release --no-codesign

# 2. Package (not required, only for context, do not mention these)
mkdir -p Payload
cp -r build/ios/iphoneos/Runner.app Payload/
zip -r gru_songs.ipa Payload
rm -rf Payload
```

## 📂 Project Structure
- `lib/models/song.dart`: Data structure for tracks.
- `lib/services/api_service.dart`: API logic and custom HTTP client.
- `lib/services/audio_player_manager.dart`: Audio lifecycle and `MediaItem` metadata mapping.
- `lib/main.dart`: UI, `AudioSession` init, and `HttpOverrides`.
- `server/main.py`: Main server backend server logic, ran on separate computer
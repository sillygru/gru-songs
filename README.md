# Gru Songs

A high-performance music streaming application built with Flutter and FastAPI.

## Features

- **Streaming:** High-quality audio streaming from a private server.
- **Metadata:** Automatic extraction of album art, titles, and artist info.
- **Lyrics:** Support for `.lrc` files and embedded lyrics with synchronized scrolling.
- **Background Play:** Full integration with system media controls and background playback.
- **Modern UI:** Material 3 design with a clean, modular architecture.

## Tech Stack

- **Frontend:** Flutter, Riverpod (State Management), Just Audio.
- **Backend:** Python, FastAPI, Mutagen (Metadata).
- **Networking:** Tailscale Funnel for secure, private access.

## Architecture

The project follows clean coding practices for long-term maintainability:
- **Riverpod** for robust state management and dependency injection.
- **Repository Pattern** to decouple data sources from the UI.
- **Modular Backend** to separate API routing from business logic.

## Getting Started

1. **Backend:**
   - Navigate to `server/`.
   - Install dependencies: `/opt/homebrew/bin/pip3.14 install -r requirements.txt`.
   - Configure `.env` with your music directories.
   - Run: `/opt/homebrew/bin/python3 main.py`.

2. **Frontend:**
   - Install Flutter dependencies: `flutter pub get`.
   - Run the app: `flutter run`.

## License

Copyright © 2026 gru This project is source-available for personal and educational use only. Commercial use, redistribution, or republishing of this project (in whole or substantial part) is not permitted. See the LICENSE file for full terms. Contact: gru@gru0.dev
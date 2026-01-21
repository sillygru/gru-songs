# Gru Songs (v7.0.2)

## ⚠️ This is a vibe coded mess of a project !! ⚠️
Meaning, don't expect everything to work perfectly, half broken features should be expected.

## What is Gru Songs?
Gru Songs is a simple local music player app built with Flutter, that can optionally connect to a server to sync stats.

## Features

- **Folder Based Organization:** Organize your music with intuitive folder structure support.
- **Metadata:** Automatic extraction of album art, titles, and artist info.
- **Lyrics:** Support for `.lrc` files and embedded lyrics with synchronized scrolling.
- **Background Play:** Full integration with system media controls and background playback.

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

Simply install the app from the releases page, by default it will use my private server for stat syncing.

### Good to know

User data is purely based off filenames, so if you rename a file, data associated to it will be reset. (Stats, wether or not it was favorited/suggested less, will affect shuffle personality)

## For developers / if you want to run your own private server
1. **Backend:**
   - Clone the repo
   - Navigate to `server/`.
   - Install dependencies: `pip install -r requirements.txt`.
   - Configure `.env` if you  want to use the discord bot for logging. (check .env.example)
   - Run: `python main.py`.

2. **Frontend:**
   - Install Flutter dependencies: `flutter pub get`.
   - Run the app: `flutter run`.

## License

Copyright © 2026 gru This project is source-available for personal and educational use only. Commercial use, redistribution, or republishing of this project (in whole or substantial part) is not permitted. See the LICENSE file for full terms. Contact: gru@gru0.dev
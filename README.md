# Gru Songs (v3.3.0)

## What is Gru Songs?
Gru Songs is a simple local music player app built with Flutter, that can optionally connect to a server to sync stats.

## Features

- **Folder Based Organization:** Organize your music with intuitive folder structure support.
- **Metadata:** Automatic extraction of album art, titles, and artist info.
- **Lyrics:** Support for `.lrc` files and embedded lyrics with synchronized scrolling.

## Getting Started

Simply install the app from the releases page.
If you want to sync data across devices, you must host your own server.

### Good to know

User data in Gru Songs is tied to the music file's name. If you rename a file outside of the Gru Songs app (such as with your file manager), any stats and preferences linked to that file—like play count, favorites, or "suggest less" status will be lost or reset. This can also impact shuffle personality weight system.
We do have a feature to sync file names across devices :)

### Others
This is a vibe coded project, if features are half-broken, that is normal.
This was originally a personal side project, so there might be leftovers of pre-configured stuff of when this was only meant for my personal use (mostly server stuff, frontend's great on this aspect)

## For developers / if you want to run your own private server
1. **Backend:**
   - Clone the repo
   - Navigate to `server/`.
   - Install dependencies: `pip install -r requirements.txt`.
   - Run: `python main.py`.
      - It will guide you trough a first time setup.

2. **Frontend:**
### Run the app
   - Install Flutter dependencies: `flutter pub get`.
   - Run the app: `flutter run`.

### Build the app for different platforms
   - flutter build apk --release
   - flutter build ios --release
   - flutter build macos --release


## Ignore/notes to self
### Versioning rules:
- This project uses major.minor.patch versioning format.
   - Version numbering is based on update impact

## License

Copyright © 2026 gru This project is source-available for personal and educational use only. Commercial use, redistribution, or republishing of this project (in whole or substantial part) is not permitted. See the LICENSE file for full terms. Contact: gru@gru0.dev
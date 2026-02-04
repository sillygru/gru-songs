# Gru Songs (v3.12.1)

## What is Gru Songs?
Gru Songs is a simple local music player app built with Flutter.

[Features](#features) | [Additional Features](#additional-features) | [Getting Started](#getting-started) | [Good to know](#good-to-know) | [Others](#others) | [Screenshots](#screenshots)

## Features
- **Shuffle personalities:** Multiple shuffle personalities, default, explorer and consistent
- **Folder Based Organization:** Organize your music with intuitive folder structure support while also supporting playlists.
- **Metadata Editing:** Built-in editor for modifying song metadata (title, artist, album, filename, lyrics)
- **Lyrics:** Support for `.lrc` files and embedded lyrics with synchronized scrolling.
- **Merged Songs:** Combine multiple versions of a track (remixes, live, etc.) into a single group for shuffle, keeping individual favorites and settings.
- **Smart indexing for search:** When searching, song lyrics, albums and artists are all indexed for quick searches

## Additional Features
- **Backups:** Backup management system
- **Data Export:** Export user data and databases for backup and migration purposes
- **Volume Monitoring:** Auto-pause playback when volume is muted and resume when restored
- **Theme Selection:** Multiple theme options
- **Statistics Tracking:** Collects stats (real)
- **User Profiles:** Multi-user support with individual profiles and settings (who tf woud use this)

## Getting Started

Simply install the app from the releases page.

## Good to know

User data in Gru Songs is tied to the music file's name. If you rename a file outside of the Gru Songs app (such as with your file manager), any stats and preferences linked to that file such as play count, favorites, or "suggest less" status will be lost or reset. This can also impact shuffle personality weight system.

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image01.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image02.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image03.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image04.jpg" width="200" />
</p>

## Others
### *"Don't mind half broken features"*
This is a vibe coded project, if features are half-broken, that is... unfortunate.
This was originally a personal side project, so there might be leftovers of pre-configured stuff of when this was only meant for my personal use.

## For developers
### Run the app
   - Install Flutter dependencies: `flutter pub get`.
   - Run the app: `flutter run`.

### Build the app for Android

- **ARMv8 (arm64):**
  - `flutter build apk --release --target-platform=android-arm64`
- **ARMv7:**
  - `flutter build apk --release --target-platform=android-arm`

## License

Copyright © 2026 gru This project is source-available for personal and educational use only. Commercial use, redistribution, or republishing of this project (in whole or substantial part) is not permitted. See the LICENSE file for full terms. Contact: gru@gru0.dev
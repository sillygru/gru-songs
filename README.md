# Gru Songs (v3.8.2)

## What is Gru Songs?
Gru Songs is a simple local music player app built with Flutter.

[Features](#features) | [Getting Started](#getting-started) | [Good to know](#good-to-know) | [Others](#others) | [Screenshots](#screenshots)

## Features
- **Smart Shuffle:** Intelligent shuffle algorithm that learns from your listening habits.
- **Folder Based Organization:** Organize your music with intuitive folder structure support while also supporting playlists.
- **Metadata:** Automatic extraction of album art, titles, and artist info.
- **Lyrics:** Support for `.lrc` files and embedded lyrics with synchronized scrolling.

## Getting Started

Simply install the app from the releases page.

## Good to know

User data in Gru Songs is tied to the music file's name. If you rename a file outside of the Gru Songs app (such as with your file manager), any stats and preferences linked to that file—like play count, favorites, or "suggest less" status will be lost or reset. This can also impact shuffle personality weight system.

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image01.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image02.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image03.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image04.jpg" width="200" />
</p>

## Others
### "*Don't mind half broken features*"
This is a vibe coded project, if features are half-baked, that is normal.
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


## Random stuff i dont know where to put
### Versioning rules:
- This project uses major.minor.patch versioning format.
   - Version numbering is based on update impact
   - Small feature updates are considered minor
- The app is android only, I know it works on other platforms, but I prefer to focus on android
  - I personally test the app on macos :#

## License

Copyright © 2026 gru This project is source-available for personal and educational use only. Commercial use, redistribution, or republishing of this project (in whole or substantial part) is not permitted. See the LICENSE file for full terms. Contact: gru@gru0.dev
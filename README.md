# Wispie

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3-blue.svg">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-3DDC84.svg">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.44+-02569B.svg?logo=flutter">
  <img alt="Stars" src="https://img.shields.io/github/stars/sillygru/wispie?style=flat&label=stars">
  <img alt="Downloads" src="https://img.shields.io/github/downloads/sillygru/wispie/total">
</p>

<p align="center">
  <a href="https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/sillygru/wispie/">
    <img alt="Obtainium" src="https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/badge_obtainium.png" height="50">
  </a>
</p>

A local music player that works offline and learns what you actually listen to.

[Features](#features) | [Getting Started](#getting-started) | [Important](#important) | [Screenshots](#screenshots) | [For Developers](#for-developers)

## What it does

- **Smart shuffle** - Tracks which songs you finish and skip, then plays accordingly
- **Auto-fetch metadata** - Downloads missing album art and song info
- **Timed lyrics** - Synchronized lyrics that scroll with the music
- **Lyrics translation** - Translate lyrics to your preferred language
- **File-based** - Everything is stored locally; no accounts or cloud services

## Features

### Shuffle

Wispie tracks which songs you finish and which you skip, then uses that data to pick what plays next.

- **Consistent mode** - Plays favorites more often but still introduces new tracks
- **Explorer mode** - Plays more songs you haven't heard recently
- **Custom mode** - Adjust individual weights for favorites, skips, and playlists

### Library

- **Folder browsing** - Navigate your music using your existing folder structure
- **Playlists** - Create and manage custom playlists
- **Edit metadata** - Change song titles, artist names, and album art
- **Auto-fetch metadata** - Download missing metadata and album art automatically
- **Lyrics** - View synchronized lyrics that scroll with the music
- **Lyrics translation** - Translate lyrics to your preferred language
- **Video support** - Play video files as audio

### Organization

- **Merged songs** - Group different versions (remixes, live, acoustic) so shuffle treats them as one
- **Search** - Search titles, artists, albums, and lyrics
- **Queue history** - Save and restore previous listening sessions
- **Backups** - Export and restore your data

### Playback

- **Dynamic themes** - Match the app theme to your album art
- **Beat visualization** - The player reacts to the music's beat
- **Waveform display** - See the audio waveform while playing
- **Crossfade** - Smooth transitions between tracks
- **Sleep timer** - Stop playback after a set time
- **Auto-pause** - Pause when volume drops to zero
- **Background art fetching** - Downloads album art in the background

## Getting Started

### Installation

Download the latest release from the releases page and install it on your Android device.

### Setup

1. Grant storage permissions
2. Select your music folders
3. Start listening

## Important

### File names

Wispie links your data (favorites, play counts) to file names. If you rename a file outside the app, that song's history resets.

### Offline

The app works without internet. Your music and data stay on your device.

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image01.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image02.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image03.jpg" width="200" />
  <img src="https://raw.githubusercontent.com/sillygru/gru-songs/main/assets/screenshots/image04.jpg" width="200" />
</p>

## Telemetry

Wispie can send anonymous startup events to count installations. No personal data (names, emails, file paths, IPs) is collected. Each installation uses a random UUID.

Disable this in Settings > Privacy. When disabled, nothing is sent.

Telemetry only works when built with a `TELEMETRY_SECRET` environment variable. Builds without this variable send no data.

## For Developers

### Run

```bash
flutter pub get
flutter run
```

### Build Android

```bash
# ARMv8 (arm64)
flutter build apk --release --target-platform=android-arm64

# ARMv7
flutter build apk --release --target-platform=android-arm
```

## License

Copyright (c) 2026 gru — Licensed under GNU General Public License v3.0.

See [LICENSE](LICENSE) for full terms.

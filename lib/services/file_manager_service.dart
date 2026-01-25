import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'database_service.dart';
import 'api_service.dart';
import '../models/song.dart';
import 'storage_service.dart';

class FileManagerService {
  final ApiService _apiService;

  FileManagerService(this._apiService);

  /// Updates the song title in the file metadata and notifies the server.
  Future<void> updateSongTitle(Song song, String newTitle,
      {int deviceCount = 0}) async {
    // 1. Update locally
    await _updateMetadataInternal(song.url, title: newTitle);

    // 2. Notify server if not in local mode
    if (!await StorageService().getIsLocalMode()) {
      try {
        await _apiService.renameFile(song.filename, newTitle, deviceCount,
            type: "metadata");
      } catch (e) {
        debugPrint(
            "Server title update notification failed: $e. It will need manual sync later.");
      }
    }
  }

  /// Updates all metadata for a song and notifies the server.
  Future<void> updateSongMetadata(
      Song song, String title, String artist, String album,
      {int deviceCount = 0}) async {
    // 1. Update locally
    await _updateMetadataInternal(song.url,
        title: title, artist: artist, album: album);

    // 2. Notify server if not in local mode
    if (!await StorageService().getIsLocalMode()) {
      try {
        await _apiService.renameFile(song.filename, title, deviceCount,
            type: "metadata", artist: artist, album: album);
      } catch (e) {
        debugPrint(
            "Server metadata update notification failed: $e. It will need manual sync later.");
      }
    }
  }

  /// Updates lyrics for a song.
  Future<void> updateLyrics(Song song, String lyricsContent) async {
    String? lyricsPath = song.lyricsUrl;

    if (lyricsPath == null) {
      // Create new lyrics file in the lyrics folder if configured
      final lyricsFolder = await StorageService().getLyricsFolderPath();
      if (lyricsFolder != null) {
        final songTitle = p.basenameWithoutExtension(song.filename);
        lyricsPath = p.join(lyricsFolder, "$songTitle.lrc");
      } else {
        // Fallback: put it next to the song
        final songDir = p.dirname(song.url);
        final songTitle = p.basenameWithoutExtension(song.filename);
        lyricsPath = p.join(songDir, "$songTitle.lrc");
      }
    }

    try {
      final file = File(lyricsPath);
      await file.writeAsString(lyricsContent);
      debugPrint("Updated lyrics for ${song.filename} at $lyricsPath");
    } catch (e) {
      throw Exception("Failed to update lyrics: $e");
    }
  }

  /// Internal method to update metadata without server notification.
  Future<void> _updateMetadataInternal(String fileUrl,
      {String? title, String? artist, String? album}) async {
    try {
      // Read existing metadata
      final metadata = await MetadataGod.readMetadata(file: fileUrl);

      // Create updated metadata object
      final updatedMetadata = Metadata(
        title: title ?? metadata.title,
        artist: artist ?? metadata.artist,
        album: album ?? metadata.album,
        albumArtist: metadata.albumArtist,
        trackNumber: metadata.trackNumber,
        trackTotal: metadata.trackTotal,
        discNumber: metadata.discNumber,
        discTotal: metadata.discTotal,
        year: metadata.year,
        genre: metadata.genre,
        picture: metadata.picture,
      );

      // Write it back
      await MetadataGod.writeMetadata(
        file: fileUrl,
        metadata: updatedMetadata,
      );
      debugPrint("Successfully updated metadata for $fileUrl");
    } catch (e) {
      throw Exception("Failed to update song metadata: $e");
    }
  }

  /// Renames a song file locally and notifies the server.
  /// [deviceCount] is the number of OTHER devices that need to sync this rename.
  Future<void> renameSong(Song song, String newTitle,
      {int deviceCount = 0}) async {
    final oldPath = song.url;
    final directory = p.dirname(oldPath);
    final extension = p.extension(oldPath);
    final newFilename = "$newTitle$extension";
    final newPath = p.join(directory, newFilename);

    if (await File(newPath).exists()) {
      throw Exception("A file with that name already exists in this folder.");
    }

    // 1. Rename physical file
    try {
      await File(oldPath).rename(newPath);
    } catch (e) {
      throw Exception("Failed to rename file on filesystem: $e");
    }

    // 2. Also rename lyrics if they exist and match the old filename
    if (song.lyricsUrl != null) {
      final oldLyricsFile = File(song.lyricsUrl!);
      if (await oldLyricsFile.exists()) {
        final lyricsDir = p.dirname(song.lyricsUrl!);
        final lyricsExt = p.extension(song.lyricsUrl!);
        final newLyricsPath = p.join(lyricsDir, "$newTitle$lyricsExt");
        try {
          await oldLyricsFile.rename(newLyricsPath);
        } catch (e) {
          debugPrint("Failed to rename lyrics file: $e");
        }
      }
    }

    // 3. Update local DB
    await DatabaseService.instance.renameFile(song.filename, newFilename);

    // 3. Notify server if not in local mode
    if (!await StorageService().getIsLocalMode()) {
      try {
        await _apiService.renameFile(song.filename, newFilename, deviceCount,
            type: "file");
      } catch (e) {
        debugPrint(
            "Server rename notification failed: $e. It will need manual sync later.");
      }
    }

    debugPrint("Successfully renamed ${song.filename} to $newFilename");
  }

  /// Deletes a song file from the filesystem.
  Future<void> deleteSongFile(Song song) async {
    final file = File(song.url);
    if (await file.exists()) {
      await file.delete();
      debugPrint("Deleted file: ${song.url}");
    } else {
      throw Exception("File does not exist: ${song.url}");
    }
  }

  /// Checks for renames performed on other devices and applies them locally.
  Future<void> syncRenamesFromServer(String rootPath) async {
    if (await StorageService().getIsLocalMode()) return;

    try {
      final pending = await _apiService.getPendingRenames();
      if (pending.isEmpty) return;

      // We need to find the files by their basename in the rootPath
      final allFiles = _listAllAudioFiles(Directory(rootPath));

      for (var task in pending) {
        final oldName = task['old'] as String;
        final newName = task['new'] as String;
        final type = task['type'] as String? ?? "file";

        // Find the file locally
        File? localFile;
        for (var file in allFiles) {
          if (p.basename(file.path) == oldName) {
            localFile = file;
            break;
          }
        }

        if (localFile != null) {
          if (type == "file") {
            // Physical Rename Sync
            final directory = p.dirname(localFile.path);
            final targetPath = p.join(directory, newName);

            if (!await File(targetPath).exists()) {
              try {
                await localFile.rename(targetPath);
                await DatabaseService.instance.renameFile(oldName, newName);
                await _apiService.acknowledgeRename(oldName, newName,
                    type: "file");
                debugPrint("Applied remote file rename: $oldName -> $newName");
              } catch (e) {
                debugPrint("Failed to apply remote rename for $oldName: $e");
              }
            } else {
              await DatabaseService.instance.renameFile(oldName, newName);
              await _apiService.acknowledgeRename(oldName, newName,
                  type: "file");
            }
          } else {
            // Metadata Title/Artist/Album Sync
            try {
              final artist = task['artist'] as String?;
              final album = task['album'] as String?;
              await _updateMetadataInternal(localFile.path,
                  title: newName, artist: artist, album: album);
              await _apiService.acknowledgeRename(oldName, newName,
                  type: "metadata", artist: artist, album: album);
              debugPrint(
                  "Applied remote metadata update: $oldName -> $newName (Artist: $artist, Album: $album)");
            } catch (e) {
              debugPrint(
                  "Failed to apply remote metadata update for $oldName: $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Sync renames from server failed: $e");
    }
  }

  List<File> _listAllAudioFiles(Directory dir) {
    final List<File> audioFiles = [];
    final supported = ['.mp3', '.m4a', '.wav', '.flac', '.ogg'];

    if (!dir.existsSync()) return [];

    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (var entity in entities) {
        if (entity is File &&
            supported.contains(p.extension(entity.path).toLowerCase())) {
          audioFiles.add(entity);
        }
      }
    } catch (e) {
      debugPrint("Error listing files for rename sync: $e");
    }
    return audioFiles;
  }
}

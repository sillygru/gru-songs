import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'database_service.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'android_storage_service.dart';

class FileManagerService {
  /// Updates the song title in the file metadata.
  Future<void> updateSongTitle(Song song, String newTitle) async {
    debugPrint(
        'FileManager: updateSongTitle called for ${song.filename} -> $newTitle');

    try {
      // 1. Update locally
      debugPrint('FileManager: Starting local metadata update...');
      await _updateMetadataInternal(song.url, title: newTitle);
      debugPrint('FileManager: Local metadata update successful');
    } catch (e) {
      debugPrint('FileManager: updateSongTitle failed: $e');
      rethrow;
    }
  }

  /// Updates all metadata for a song.
  Future<void> updateSongMetadata(
      Song song, String title, String artist, String album) async {
    // 1. Update locally
    await _updateMetadataInternal(song.url,
        title: title, artist: artist, album: album);
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

  /// Internal method to update metadata.
  Future<void> _updateMetadataInternal(String fileUrl,
      {String? title, String? artist, String? album}) async {
    try {
      if (Platform.isAndroid) {
        final storage = StorageService();
        final treeUri = await storage.getMusicFolderTreeUri();
        final rootPath = await storage.getMusicFolderPath();
        if (treeUri != null && treeUri.isNotEmpty && rootPath != null) {
          if (!p.isWithin(rootPath, fileUrl) &&
              !p.equals(rootPath, p.dirname(fileUrl))) {
            throw Exception('Source file is outside the music folder.');
          }

          final tempDir = await Directory.systemTemp.createTemp('gru_meta_');
          final tempFile = File(p.join(tempDir.path, p.basename(fileUrl)));
          await File(fileUrl).copy(tempFile.path);

          final metadata = await MetadataGod.readMetadata(file: tempFile.path);
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

          await MetadataGod.writeMetadata(
            file: tempFile.path,
            metadata: updatedMetadata,
          );

          final sourceRelativePath = p.relative(fileUrl, from: rootPath);
          await AndroidStorageService.writeFileFromPath(
            treeUri: treeUri,
            sourceRelativePath: sourceRelativePath,
            sourcePath: tempFile.path,
          );

          await tempDir.delete(recursive: true);
          debugPrint("Successfully updated metadata for $fileUrl");
          return;
        }
      }

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

  /// Renames a song file locally.
  Future<void> renameSong(Song song, String newTitle) async {
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
      if (Platform.isAndroid) {
        final storage = StorageService();
        final treeUri = await storage.getMusicFolderTreeUri();
        final rootPath = await storage.getMusicFolderPath();
        if (treeUri != null && treeUri.isNotEmpty && rootPath != null) {
          if (!p.isWithin(rootPath, oldPath) &&
              !p.equals(rootPath, p.dirname(oldPath))) {
            throw Exception('Source file is outside the music folder.');
          }
          final sourceRelativePath = p.relative(oldPath, from: rootPath);
          await AndroidStorageService.renameFile(
            treeUri: treeUri,
            sourceRelativePath: sourceRelativePath,
            newName: newFilename,
          );
        } else {
          await File(oldPath).rename(newPath);
        }
      } else {
        await File(oldPath).rename(newPath);
      }
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
          if (Platform.isAndroid) {
            final storage = StorageService();
            final lyricsTreeUri = await storage.getLyricsFolderTreeUri();
            final lyricsRoot = await storage.getLyricsFolderPath();
            if (lyricsTreeUri != null &&
                lyricsTreeUri.isNotEmpty &&
                lyricsRoot != null &&
                (p.isWithin(lyricsRoot, oldLyricsFile.path) ||
                    p.equals(lyricsRoot, p.dirname(oldLyricsFile.path)))) {
              final lyricsRelativePath =
                  p.relative(oldLyricsFile.path, from: lyricsRoot);
              await AndroidStorageService.renameFile(
                treeUri: lyricsTreeUri,
                sourceRelativePath: lyricsRelativePath,
                newName: "$newTitle$lyricsExt",
              );
            } else {
              await oldLyricsFile.rename(newLyricsPath);
            }
          } else {
            await oldLyricsFile.rename(newLyricsPath);
          }
        } catch (e) {
          debugPrint("Failed to rename lyrics file: $e");
        }
      }
    }

    // 3. Update local DB
    await DatabaseService.instance.renameFile(song.filename, newFilename);

    debugPrint("Successfully renamed ${song.filename} to $newFilename");
  }

  /// Deletes a song file from the filesystem.
  Future<void> deleteSongFile(Song song) async {
    if (Platform.isAndroid) {
      final storage = StorageService();
      final treeUri = await storage.getMusicFolderTreeUri();
      final rootPath = await storage.getMusicFolderPath();
      if (treeUri != null && treeUri.isNotEmpty && rootPath != null) {
        if (!p.isWithin(rootPath, song.url) &&
            !p.equals(rootPath, p.dirname(song.url))) {
          throw Exception('Source file is outside the music folder.');
        }
        final sourceRelativePath = p.relative(song.url, from: rootPath);
        await AndroidStorageService.deleteFile(
          treeUri: treeUri,
          sourceRelativePath: sourceRelativePath,
        );
        debugPrint("Deleted file: ${song.url}");
        return;
      }
    }

    final file = File(song.url);
    if (await file.exists()) {
      await file.delete();
      debugPrint("Deleted file: ${song.url}");
    } else {
      throw Exception("File does not exist: ${song.url}");
    }
  }
}

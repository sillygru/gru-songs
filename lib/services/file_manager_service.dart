import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
      await updateMetadataInternal(song.url, title: newTitle);
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
    await updateMetadataInternal(song.url,
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

  /// Updates the song cover art.
  /// [imagePath] is the path to the new image file. If null, the cover is removed.
  Future<String?> updateSongCover(Song song, String? imagePath) async {
    debugPrint('FileManager: updateSongCover called for ${song.filename}');

    try {
      Picture? newPicture;
      if (imagePath != null) {
        final file = File(imagePath);
        if (!await file.exists()) {
          throw Exception("Image file not found: $imagePath");
        }

        // Basic validation
        final length = await file.length();
        if (length > 10 * 1024 * 1024) {
          // 10MB limit
          throw Exception("Image file too large (max 10MB)");
        }

        final bytes = await file.readAsBytes();

        // Validate image dimensions and format in a separate isolate
        final image = await compute(_decodeImage, bytes);

        if (image == null) {
          throw Exception("Invalid or unsupported image format");
        }
        if (image.width < 50 || image.height < 50) {
          throw Exception("Image too small (minimum 50x50 pixels)");
        }

        final mimeType = _getMimeTypeFromExtension(p.extension(imagePath));

        newPicture = Picture(
          mimeType: mimeType,
          data: bytes,
        );
      }

      // 1. Update ID3 tag
      await updateMetadataInternal(song.url,
          picture: newPicture, removePicture: imagePath == null);

      // 2. Update cached extracted cover
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(song.url)).toString();

      // Clean up old cached files for this song (including timestamped ones)
      try {
        final files = await coversDir.list().toList();
        for (final entity in files) {
          if (entity is File) {
            final filename = p.basename(entity.path);
            if (filename.startsWith(hash)) {
              await entity.delete();
            }
          }
        }
      } catch (e) {
        debugPrint("Error cleaning up old covers: $e");
      }

      if (imagePath != null) {
        // Get the new mtime of the file
        final songFile = File(song.url);
        final stat = await songFile.stat();
        final mtimeMs = stat.modified.millisecondsSinceEpoch;

        final ext = p.extension(imagePath).toLowerCase();
        // Add mtime to ensure unique filename and bust cache, and allow ScannerService to verify validity
        final newCoverFile =
            File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
        await newCoverFile.writeAsBytes(newPicture!.data);
        return newCoverFile.path;
      }

      return null;
    } catch (e) {
      debugPrint('FileManager: updateSongCover failed: $e');
      rethrow;
    }
  }

  /// Gets the bytes for exporting the song cover (as JPG).
  Future<Uint8List> getCoverExportBytes(Song song) async {
    if (song.coverUrl == null) {
      throw Exception("No cover available to export");
    }

    final coverFile = File(song.coverUrl!);
    if (!await coverFile.exists()) {
      throw Exception("Cover file not found at ${song.coverUrl}");
    }

    try {
      // Decode the image to ensure it's valid and to re-encode as JPG
      final bytes = await coverFile.readAsBytes();
      
      // Run heavy image processing in an isolate
      return await compute(_processImageForExport, bytes);
    } catch (e) {
      throw Exception("Failed to export cover: $e");
    }
  }

  /// Exports the current song cover to the specified path.
  Future<void> exportSongCover(Song song, String destinationPath) async {
    final jpgBytes = await getCoverExportBytes(song);
    await File(destinationPath).writeAsBytes(jpgBytes);
  }

  // Top-level function for compute
  static img.Image? _decodeImage(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (e) {
      return null;
    }
  }

  // Top-level function for compute
  static Uint8List _processImageForExport(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception("Could not decode cover image");
    }
    // Encode as JPG with 85% quality
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  String _getMimeTypeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  @visibleForTesting
  Future<void> updateMetadataInternal(String fileUrl,
      {String? title,
      String? artist,
      String? album,
      Picture? picture,
      bool removePicture = false}) async {
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
            picture: removePicture ? null : (picture ?? metadata.picture),
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
        picture: removePicture ? null : (picture ?? metadata.picture),
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

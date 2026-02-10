import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:metadata_god/metadata_god.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'database_service.dart';
import 'scanner_service.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'android_storage_service.dart';
import 'ffmpeg_service.dart';

class FileManagerService {
  Future<RandomAccessFile?> _acquireExclusiveLock(String fileUrl) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final lockDir = Directory(p.join(supportDir.path, 'file_locks'));
      if (!await lockDir.exists()) {
        await lockDir.create(recursive: true);
      }
      final hash = md5.convert(utf8.encode(fileUrl)).toString();
      final lockFile = File(p.join(lockDir.path, '$hash.lock'));
      final raf = await lockFile.open(mode: FileMode.append);
      await raf.lock(FileLock.exclusive);
      return raf;
    } catch (e) {
      debugPrint('FileManager: failed to acquire lock for $fileUrl: $e');
      return null;
    }
  }

  Future<void> _releaseLock(RandomAccessFile? raf) async {
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (_) {
      // Best-effort unlock
    }
    try {
      await raf.close();
    } catch (_) {
      // Ignore close errors
    }
  }

  Future<Map<String, String>?> _getMatchingMusicFolder(String fileUrl) async {
    final storage = StorageService();
    final musicFolders = await storage.getMusicFolders();
    for (final folder in musicFolders) {
      final path = folder['path'];
      if (path == null || path.isEmpty) continue;
      if (p.isWithin(path, fileUrl) || p.equals(path, p.dirname(fileUrl))) {
        return folder;
      }
    }
    return null;
  }

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

      final ext = p.extension(song.url).toLowerCase();
      final isMp4Container = ext == '.m4a' || ext == '.mp4';

      // 1. Update metadata in the actual song file
      if (isMp4Container && Platform.isAndroid) {
        await _updateCoverWithFFmpeg(song.url, imagePath);
      } else {
        await updateMetadataInternal(song.url,
            picture: newPicture, removePicture: imagePath == null);
      }

      // 2. Rebuild the cover cache for this specific song from the actual file
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(song.url)).toString();

      // Clean up ALL old cached files for this song
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
        final songFile = File(song.url);
        final stat = await songFile.stat();
        final mtimeMs = stat.modified.millisecondsSinceEpoch;

        // Re-extract the cover from the actual file on disk to verify the
        // metadata write persisted and to build the cache using the exact same
        // logic the scanner/rebuild uses.  Skip folder covers — we are setting
        // a per-song cover, not picking up a shared folder image.
        String? extractedPath;
        try {
          extractedPath = await ScannerService.extractCoverForFile(
            songFile,
            coversDir,
            hash,
            mtimeMs,
            skipFolderCover: true,
          );
        } catch (e) {
          debugPrint(
              'FileManager: re-extraction after metadata write failed: $e');
        }

        if (extractedPath != null) {
          debugPrint(
              'FileManager: verified cover persisted in file → $extractedPath');
          return extractedPath;
        }

        // Fallback: the metadata write may not have been readable by the
        // extraction libraries, but we know the bytes are correct so write
        // them to cache directly.
        debugPrint(
            'FileManager: extraction could not read back cover, writing bytes directly');
        final ext = p.extension(imagePath).toLowerCase();
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

  Future<void> _updateCoverWithFFmpeg(String fileUrl, String? imagePath) async {
    final matchingFolder = await _getMatchingMusicFolder(fileUrl);
    final treeUri = matchingFolder?['treeUri'];
    final rootPath = matchingFolder?['path'];

    final tempDir = await Directory.systemTemp.createTemp('gru_ffmpeg_');
    final ext = p.extension(fileUrl).toLowerCase();
    final tempOut = File(p.join(tempDir.path, 'out$ext'));

    final ffmpeg = FFmpegService();
    await ffmpeg.embedCover(
      inputPath: fileUrl,
      outputPath: tempOut.path,
      imagePath: imagePath,
    );

    if (Platform.isAndroid &&
        treeUri != null &&
        treeUri.isNotEmpty &&
        rootPath != null &&
        rootPath.isNotEmpty) {
      if (!p.isWithin(rootPath, fileUrl) &&
          !p.equals(rootPath, p.dirname(fileUrl))) {
        throw Exception('Source file is outside the music folder.');
      }
      final sourceRelativePath = p.relative(fileUrl, from: rootPath);
      await AndroidStorageService.writeFileFromPath(
        treeUri: treeUri,
        sourceRelativePath: sourceRelativePath,
        sourcePath: tempOut.path,
      );
    } else {
      final original = File(fileUrl);
      final backup = File('$fileUrl.bak');
      if (await backup.exists()) {
        await backup.delete();
      }
      await original.rename(backup.path);
      await tempOut.rename(original.path);
      await backup.delete();
    }

    await tempDir.delete(recursive: true);
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

  /// Fixes the song cover by trimming black borders and cropping to a square.
  /// Returns a list of fixed image options.
  /// The first option is the standard auto-crop.
  /// Subsequent options are alternatives (e.g., symmetrical crop).
  Future<List<Uint8List>> getFixedCoverOptions(Song song) async {
    if (song.coverUrl == null) {
      throw Exception("No cover available to fix");
    }

    final coverFile = File(song.coverUrl!);
    if (!await coverFile.exists()) {
      throw Exception("Cover file not found at ${song.coverUrl}");
    }

    try {
      final bytes = await coverFile.readAsBytes();
      return await compute(_processFixOptions, bytes);
    } catch (e) {
      throw Exception("Failed to fix cover: $e");
    }
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

  // Top-level function for compute
  static List<Uint8List> _processFixOptions(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception("Could not decode cover image");
    }

    // 1. Detect Content Bounding Box
    int minX = image.width;
    int minY = image.height;
    int maxX = 0;
    int maxY = 0;

    bool foundContent = false;
    const threshold = 45; // Tolerance for "black"/noise

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Access r, g, b directly from pixel
        if (pixel.r > threshold || pixel.g > threshold || pixel.b > threshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          foundContent = true;
        }
      }
    }

    // Helper to square crop and encode
    Uint8List squareCropAndEncode(img.Image imgToCrop) {
      img.Image cropped = imgToCrop;
      if (cropped.width != cropped.height) {
        int size =
            cropped.width < cropped.height ? cropped.width : cropped.height;
        int xOffset = (cropped.width - size) ~/ 2;
        int yOffset = (cropped.height - size) ~/ 2;

        cropped = img.copyCrop(cropped,
            x: xOffset, y: yOffset, width: size, height: size);
      }
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
    }

    if (!foundContent) {
      // If all black, just return original squared
      return [squareCropAndEncode(image)];
    }

    final results = <Uint8List>[];

    // --- Option 1: Standard (Crop to detected content) ---
    img.Image standardCrop = image;
    final trimWidth = maxX - minX + 1;
    final trimHeight = maxY - minY + 1;

    // Only crop if we actually found borders to remove
    if (trimWidth < image.width || trimHeight < image.height) {
      standardCrop = img.copyCrop(image,
          x: minX, y: minY, width: trimWidth, height: trimHeight);
    }
    results.add(squareCropAndEncode(standardCrop));

    // --- Option 2: Symmetrical Crop ---
    // Useful for cases where one side has a black border and the other has a blur/noise
    // but we want to crop symmetrically based on the detected border.

    int leftInset = minX;
    int rightInset = image.width - 1 - maxX;
    int topInset = minY;
    int bottomInset = image.height - 1 - maxY;

    int symH = max(leftInset, rightInset);
    int symV = max(topInset, bottomInset);

    // Only add if it yields a different crop rectangle than the standard one
    // Standard crop rect: x=minX, y=minY, w=trimWidth, h=trimHeight
    // Symmetrical crop rect: x=symH, y=symV, w=image.width-2*symH, h=image.height-2*symV

    bool isDifferent = (leftInset != symH) ||
        (rightInset != symH) ||
        (topInset != symV) ||
        (bottomInset != symV);

    if (isDifferent) {
      // Ensure we don't crop everything away
      if (2 * symH < image.width && 2 * symV < image.height) {
        final symWidth = image.width - 2 * symH;
        final symHeight = image.height - 2 * symV;

        final symCrop = img.copyCrop(image,
            x: symH, y: symV, width: symWidth, height: symHeight);
        results.add(squareCropAndEncode(symCrop));
      }
    }

    return results;
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
      final lock = await _acquireExclusiveLock(fileUrl);
      try {
        if (Platform.isAndroid) {
          final matchingFolder = await _getMatchingMusicFolder(fileUrl);
          final treeUri = matchingFolder?['treeUri'];
          final rootPath = matchingFolder?['path'];
          if (treeUri != null &&
              treeUri.isNotEmpty &&
              rootPath != null &&
              rootPath.isNotEmpty) {
            if (!p.isWithin(rootPath, fileUrl) &&
                !p.equals(rootPath, p.dirname(fileUrl))) {
              throw Exception('Source file is outside the music folder.');
            }

            final tempDir = await Directory.systemTemp.createTemp('gru_meta_');
            final tempFile = File(p.join(tempDir.path, p.basename(fileUrl)));
            await File(fileUrl).copy(tempFile.path);

            // Use audio_metadata_reader for cover updates and MetadataGod for text
            await _updateMetadataWithLibraries(
              tempFile: tempFile,
              tempDir: tempDir,
              title: title,
              artist: artist,
              album: album,
              picture: picture,
              removePicture: removePicture,
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

        // Fallback: update via temp file and copy back
        final tempDir = await Directory.systemTemp.createTemp('gru_meta_');
        final tempFile = File(p.join(tempDir.path, p.basename(fileUrl)));
        await File(fileUrl).copy(tempFile.path);

        await _updateMetadataWithLibraries(
          tempFile: tempFile,
          tempDir: tempDir,
          title: title,
          artist: artist,
          album: album,
          picture: picture,
          removePicture: removePicture,
        );

        await tempFile.copy(fileUrl);
        await tempDir.delete(recursive: true);
        debugPrint("Successfully updated metadata for $fileUrl");
      } finally {
        await _releaseLock(lock);
      }
    } catch (e) {
      throw Exception("Failed to update song metadata: $e");
    }
  }

  /// Helper method to update metadata using both audio_metadata_reader (for covers)
  /// and MetadataGod (for text). Works on all platforms.
  Future<void> _updateMetadataWithLibraries({
    required File tempFile,
    required Directory tempDir,
    String? title,
    String? artist,
    String? album,
    Picture? picture,
    bool removePicture = false,
  }) async {
    // For cover updates, use audio_metadata_reader with working directory workaround
    // The library has a bug where it writes to hardcoded "a_new.mp4" etc.
    if (picture != null || removePicture) {
      final originalDir = Directory.current;
      try {
        // Change to temp directory so the library creates a_new.* files there
        Directory.current = tempDir;

        amr.updateMetadata(tempFile, (metadata) {
          final amrPicture = picture != null
              ? amr.Picture(
                  Uint8List.fromList(picture.data),
                  picture.mimeType,
                  amr.PictureType.coverFront,
                )
              : null;

          // Handle different metadata types
          if (metadata is amr.Mp3Metadata) {
            if (removePicture) {
              metadata.pictures.clear();
            } else if (amrPicture != null) {
              metadata.pictures = [amrPicture];
            }
          } else if (metadata is amr.Mp4Metadata) {
            metadata.picture = removePicture ? null : amrPicture;
          } else if (metadata is amr.VorbisMetadata) {
            if (removePicture) {
              metadata.pictures.clear();
            } else if (amrPicture != null) {
              metadata.pictures = [amrPicture];
            }
          } else if (metadata is amr.RiffMetadata) {
            if (removePicture) {
              metadata.pictures.clear();
            } else if (amrPicture != null) {
              metadata.pictures = [amrPicture];
            }
          }
        });

        // The library writes to a_new.* - rename it back to original
        final extension = p.extension(tempFile.path).toLowerCase();
        String? newFileName;
        if (extension == '.mp4' || extension == '.m4a') {
          newFileName = 'a_new.mp4';
        } else if (extension == '.wav') {
          newFileName = 'a_new.wav';
        }

        if (newFileName != null) {
          final newFile = File(p.join(tempDir.path, newFileName));
          if (await newFile.exists()) {
            await newFile.rename(tempFile.path);
          }
        }
      } finally {
        Directory.current = originalDir;
      }

      // If only updating cover (no text changes), skip MetadataGod to avoid corrupting audio
      if (title == null && artist == null && album == null) {
        return;
      }
    }

    // Use MetadataGod for text metadata (works reliably)
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
      picture: metadata.picture, // Keep whatever audio_metadata_reader wrote
    );

    await MetadataGod.writeMetadata(
      file: tempFile.path,
      metadata: updatedMetadata,
    );
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
        final matchingFolder = await _getMatchingMusicFolder(oldPath);
        final treeUri = matchingFolder?['treeUri'];
        final rootPath = matchingFolder?['path'];
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
      final matchingFolder = await _getMatchingMusicFolder(song.url);
      final treeUri = matchingFolder?['treeUri'];
      final rootPath = matchingFolder?['path'];
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

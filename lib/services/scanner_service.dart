import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler
import '../models/song.dart';
import 'database_service.dart';

class ScannerService {
  static final List<String> _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg'
  ];

  Future<List<Song>> scanDirectory(String path,
      {String? lyricsPath,
      Map<String, int>? playCounts,
      void Function(double progress)? onProgress}) async {
    // Request permissions before accessing storage
    if (Platform.isAndroid) {
      // Request all relevant storage permissions
      var statusStorage = await Permission.storage.request();
      var statusMediaLibrary = await Permission.mediaLibrary.request();
      var statusManageExternalStorage =
          await Permission.manageExternalStorage.request();

      if (!statusStorage.isGranted &&
          !statusMediaLibrary.isGranted &&
          !statusManageExternalStorage.isGranted) {
        debugPrint('Storage permissions not granted. Cannot scan directory.');
        return []; // Return empty if permissions are not granted
      }
    }

    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final effectivePlayCounts =
        playCounts ?? await DatabaseService.instance.getPlayCounts();

    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    try {
      // 1. Get all entities first
      final List<FileSystemEntity> entities =
          dir.listSync(recursive: true, followLinks: false);
      final List<File> audioFiles = entities
          .whereType<File>()
          .where((f) =>
              _supportedExtensions.contains(p.extension(f.path).toLowerCase()))
          .toList();

      final Map<String, String?> folderCoverCache = {};

      // 2. Process in chunks or parallel to speed up (using Future.wait for I/O bound parts)
      // But since metadata reading is CPU bound and sync, we process carefully
      final List<Song> songs = [];

      for (int i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        final song = await _processSingleFile(
            file, coversDir, folderCoverCache, lyricsPath, effectivePlayCounts);
        songs.add(song);

        if (onProgress != null) {
          onProgress((i + 1) / audioFiles.length);
        }
      }

      return songs;
    } catch (e) {
      debugPrint('Error scanning directory: $e');
    }

    return [];
  }

  Future<Song> _processSingleFile(
      File file,
      Directory coversDir,
      Map<String, String?> folderCoverCache,
      String? lyricsPath,
      Map<String, int> playCounts) async {
    final filename = p.basename(file.path);
    final parentPath = file.parent.path;
    p.extension(file.path).toLowerCase();

    String title = p.basenameWithoutExtension(file.path);
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration? duration;
    String? coverUrl;

    try {
      // Use compute-like behavior or just try-catch block
      final metadata = amr.readMetadata(file);
      if (metadata.title?.isNotEmpty == true) title = metadata.title!;
      if (metadata.artist?.isNotEmpty == true) artist = metadata.artist!;
      if (metadata.album?.isNotEmpty == true) album = metadata.album!;
      duration = metadata.duration;

      if (metadata.pictures.isNotEmpty) {
        final picture = metadata.pictures.first;
        final hash = md5.convert(utf8.encode(file.path)).toString();
        final coverExt = _getExtFromMime(picture.mimetype);
        final coverFile = File(p.join(coversDir.path, '$hash$coverExt'));

        // Only write if doesn't exist to save time
        if (!coverFile.existsSync()) {
          await coverFile.writeAsBytes(picture.bytes);
        }
        coverUrl = coverFile.path;
      }
    } catch (e) {
      // Silently fail primary and move to manual
    }

    // Manual Fallback for covers
    coverUrl ??= await _tryManualCoverExtraction(file, coversDir);

    // Folder-sidecar fallback
    coverUrl ??= folderCoverCache.putIfAbsent(
        parentPath, () => _findCoverInFolder(parentPath));

    String? lyricsUrl;
    if (lyricsPath != null) {
      lyricsUrl = await _findLyricsForSong(
          p.basenameWithoutExtension(file.path), lyricsPath);
    }

    return Song(
      title: title,
      artist: artist,
      album: album,
      filename: filename,
      url: file.path,
      coverUrl: coverUrl,
      lyricsUrl: lyricsUrl,
      playCount: playCounts[filename] ?? 0,
      duration: duration,
      mtime: file.statSync().modified.millisecondsSinceEpoch / 1000.0,
    );
  }

  Future<String?> _tryManualCoverExtraction(
      File file, Directory coversDir) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final length = await raf.length();
      final hash = md5.convert(utf8.encode(file.path)).toString();
      final ext = p.extension(file.path).toLowerCase();

      final bool scanEverything = length < 50 * 1024 * 1024;
      final firstScanSize = scanEverything ? length : 15 * 1024 * 1024;

      await raf.setPosition(0);
      final headerChunk = await raf.read(firstScanSize);

      if (ext == '.m4a') {
        final covrResult =
            await _scanForCovrBox(headerChunk, raf, 0, coversDir, hash);
        if (covrResult != null) return covrResult;
      }

      final apicResult =
          await _scanForAPIC(headerChunk, raf, 0, coversDir, hash);
      if (apicResult != null) return apicResult;

      final sigResult =
          await _scanBufferForSignatures(headerChunk, raf, 0, coversDir, hash);
      if (sigResult != null) return sigResult;

      if (!scanEverything && length > firstScanSize) {
        final footerSize = (10 * 1024 * 1024).clamp(0, length - firstScanSize);
        await raf.setPosition(length - footerSize);
        final footerChunk = await raf.read(footerSize);

        final sigFooterResult = await _scanBufferForSignatures(
            footerChunk, raf, length - footerSize, coversDir, hash);
        if (sigFooterResult != null) return sigFooterResult;
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<String?> _scanForAPIC(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String hash) async {
    for (int i = 0; i < bytes.length - 20; i++) {
      if (bytes[i] == 0x41 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x49 &&
          bytes[i + 3] == 0x43) {
        int tagSize = (bytes[i + 4] << 21) |
            (bytes[i + 5] << 14) |
            (bytes[i + 6] << 7) |
            bytes[i + 7];
        if (tagSize > 5000 && tagSize < 15 * 1024 * 1024) {
          final subChunk =
              bytes.sublist(i, (i + tagSize + 20).clamp(0, bytes.length));
          return await _scanBufferForSignatures(
              subChunk, raf, offset + i, coversDir, hash);
        }
      }
    }
    return null;
  }

  Future<String?> _scanForCovrBox(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String hash) async {
    for (int i = 0; i < bytes.length - 24; i++) {
      if (bytes[i] == 0x63 &&
          bytes[i + 1] == 0x6F &&
          bytes[i + 2] == 0x76 &&
          bytes[i + 3] == 0x72) {
        for (int j = i + 4; j < i + 128 && j < bytes.length - 16; j++) {
          if (bytes[j] == 0x64 &&
              bytes[j + 1] == 0x61 &&
              bytes[j + 2] == 0x74 &&
              bytes[j + 3] == 0x61) {
            final dataSize = (bytes[j - 4] << 24) |
                (bytes[j - 3] << 16) |
                (bytes[j - 2] << 8) |
                bytes[j - 1];
            final imageSize = dataSize - 16;

            if (imageSize > 1024 && imageSize < 15 * 1024 * 1024) {
              final startPos = offset + j + 12;
              await raf.setPosition(startPos);
              final imgData = await raf.read(imageSize);

              String type = 'jpg';
              if (bytes[j + 11] == 14) {
                type = 'png';
              } else if (bytes[j + 11] == 27) {
                type = 'bmp';
              }

              final coverFile = File(p.join(coversDir.path, '$hash.$type'));
              await coverFile.writeAsBytes(imgData);
              return coverFile.path;
            }
          }
        }
      }
    }
    return null;
  }

  Future<String?> _scanBufferForSignatures(
      List<int> bytes,
      RandomAccessFile raf,
      int offset,
      Directory coversDir,
      String hash) async {
    for (int i = 0; i < bytes.length - 8; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
        final res =
            await _extractImageAt(raf, offset + i, 'jpg', coversDir, hash);
        if (res != null) return res;
      }
      if (bytes[i] == 0x89 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x4E &&
          bytes[i + 3] == 0x47) {
        final res =
            await _extractImageAt(raf, offset + i, 'png', coversDir, hash);
        if (res != null) return res;
      }
      if (bytes[i] == 0x52 &&
          bytes[i + 1] == 0x49 &&
          bytes[i + 2] == 0x46 &&
          bytes[i + 3] == 0x46) {
        if (i + 12 <= bytes.length &&
            bytes[i + 8] == 0x57 &&
            bytes[i + 9] == 0x45 &&
            bytes[i + 10] == 0x42 &&
            bytes[i + 11] == 0x50) {
          final res =
              await _extractImageAt(raf, offset + i, 'webp', coversDir, hash);
          if (res != null) return res;
        }
      }
    }
    return null;
  }

  Future<String?> _extractImageAt(RandomAccessFile raf, int pos, String type,
      Directory coversDir, String hash) async {
    await raf.setPosition(pos);
    final data = await raf.read(15 * 1024 * 1024);

    int actualEnd = data.length;
    if (type == 'jpg') {
      int lastFFD9 = -1;
      for (int k = 0; k < data.length - 1; k++) {
        if (data[k] == 0xFF && data[k + 1] == 0xD9) {
          lastFFD9 = k + 2;
          if (k + 4 < data.length) {
            if (data[k + 2] != 0xFF || data[k + 3] == 0x00) {
              actualEnd = lastFFD9;
              break;
            }
          }
        }
      }
      if (lastFFD9 != -1) actualEnd = lastFFD9;
      if (actualEnd == data.length && data.length < 50 * 1024) return null;
    } else if (type == 'png') {
      final pngEnd = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82];
      for (int k = 0; k < data.length - pngEnd.length; k++) {
        bool match = true;
        for (int l = 0; l < pngEnd.length; l++) {
          if (data[k + l] != pngEnd[l]) {
            match = false;
            break;
          }
        }
        if (match) {
          actualEnd = k + pngEnd.length;
          break;
        }
      }
    }

    if (actualEnd > 1024) {
      final coverFile = File(p.join(coversDir.path, '$hash.$type'));
      await coverFile.writeAsBytes(data.sublist(0, actualEnd));
      return coverFile.path;
    }
    return null;
  }

  String _getExtFromMime(String? mimeType) {
    if (mimeType == null) return '.jpg';
    final mime = mimeType.toLowerCase();
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('gif')) return '.gif';
    return '.jpg';
  }

  String? _findCoverInFolder(String folderPath) {
    final possibleNames = [
      'cover.jpg',
      'cover.png',
      'folder.jpg',
      'folder.png',
      'album.jpg',
      'album.png'
    ];
    for (final name in possibleNames) {
      final file = File(p.join(folderPath, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  Future<String?> _findLyricsForSong(String title, String lyricsPath) async {
    final possibleNames = ['$title.lrc', '$title.txt'];
    for (final name in possibleNames) {
      final file = File(p.join(lyricsPath, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }
}

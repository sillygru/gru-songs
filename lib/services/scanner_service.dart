import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'database_service.dart';
import '../domain/services/search_service.dart';
import 'storage_service.dart';
import 'ffmpeg_service.dart';

class _ScanParams {
  final List<String> paths;
  final List<String> excludedFolders;
  final List<Song>? existingSongs;
  final String coversDirPath;
  final String lockDirPath;
  final Map<String, int> playCounts;
  final SendPort sendPort;

  _ScanParams({
    required this.paths,
    required this.excludedFolders,
    this.existingSongs,
    required this.coversDirPath,
    required this.lockDirPath,
    required this.playCounts,
    required this.sendPort,
  });
}

class _RebuildParams {
  final List<Song> songs;
  final String coversDirPath;
  final String lockDirPath;
  final SendPort sendPort;
  final bool force;

  _RebuildParams({
    required this.songs,
    required this.coversDirPath,
    required this.lockDirPath,
    required this.sendPort,
    this.force = false,
  });
}

class ScannerService {
  static final List<String> _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
    '.wma',
    '.aac',
    '.m4b',
    '.mp4',
    '.opus'
  ];

  /// Scans a specific directory for audio files (backward compatibility).
  /// Note: This method respects excluded folders from settings.
  Future<List<Song>> scanDirectory(
    String path, {
    List<Song>? existingSongs,
    String? lyricsPath,
    Map<String, int>? playCounts,
    void Function(double progress)? onProgress,
    void Function(List<Song>)? onComplete,
  }) async {
    // Check for storage permission
    if (Platform.isAndroid) {
      final statusAll = await Permission.manageExternalStorage.status;
      if (statusAll.isGranted) {
        // All files access granted: proceed without storage/audio checks.
      } else {
        var statusStorage = await Permission.storage.status;
        var statusAudio = await Permission.audio.status;

        if (!statusStorage.isGranted && !statusAudio.isGranted) {
          debugPrint('Storage permissions not granted. Cannot scan directory.');
          return [];
        }
      }
    }

    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final storage = StorageService();
    final excludedFolders = await storage.getExcludedFolders();
    final effectivePlayCounts =
        playCounts ?? await DatabaseService.instance.getPlayCounts();

    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final lockDir = Directory(p.join(supportDir.path, 'file_locks'));
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }

    final receivePort = ReceivePort();
    final params = _ScanParams(
      paths: [path],
      excludedFolders: excludedFolders,
      existingSongs: existingSongs,
      coversDirPath: coversDir.path,
      lockDirPath: lockDir.path,
      playCounts: effectivePlayCounts,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(_isolateScan, params);

    final completer = Completer<List<Song>>();
    final List<Song> allScannedSongs = [];

    receivePort.listen((message) async {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is List<Song>) {
        allScannedSongs.addAll(message);
        // Incremental DB insert to save memory and keep UI responsive
        await DatabaseService.instance.insertSongsBatch(message);
      } else if (message == 'done') {
        try {
          final searchService = SearchService();
          await searchService.init();
          await searchService.rebuildIndex(allScannedSongs);
          debugPrint(
              'Search index rebuilt with ${allScannedSongs.length} songs');
        } catch (e) {
          debugPrint('Error rebuilding search index: $e');
        }
        onComplete?.call(allScannedSongs);
        completer.complete(allScannedSongs);
        receivePort.close();
      } else if (message is String && message.startsWith('error:')) {
        receivePort.close();
        completer.completeError(message);
      }
    }, onError: (e) {
      receivePort.close();
      completer.completeError(e);
    });

    return completer.future;
  }

  /// Scans the entire device for audio files, respecting excluded folders.
  Future<List<Song>> scanDevice({
    List<Song>? existingSongs,
    List<Map<String, String>>? lyricsFolders,
    Map<String, int>? playCounts,
    void Function(double progress)? onProgress,
    void Function(List<Song>)? onComplete,
  }) async {
    // Check for all files access permission
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        debugPrint('All files access permission not granted. Cannot scan.');
        return [];
      }
    }

    final storage = StorageService();
    final excludedFolders = await storage.getExcludedFolders();
    final effectivePlayCounts =
        playCounts ?? await DatabaseService.instance.getPlayCounts();

    // Determine scan paths based on platform
    final List<String> scanPaths = [];
    if (Platform.isAndroid) {
      // Common storage locations on Android
      scanPaths.addAll([
        '/storage/emulated/0',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
      ]);
    } else if (Platform.isMacOS) {
      scanPaths.addAll([
        '${Platform.environment['HOME']}/Music',
        '/Users',
      ]);
    } else if (Platform.isWindows) {
      scanPaths.addAll([
        Platform.environment['USERPROFILE'] ?? '',
      ]);
    } else if (Platform.isLinux) {
      scanPaths.addAll([
        '${Platform.environment['HOME']}/Music',
        '${Platform.environment['HOME']}',
      ]);
    }

    // Filter to only existing paths
    final validPaths = scanPaths.where((path) {
      if (path.isEmpty) return false;
      final dir = Directory(path);
      return dir.existsSync();
    }).toList();

    if (validPaths.isEmpty) {
      debugPrint('No valid scan paths found.');
      return [];
    }

    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final lockDir = Directory(p.join(supportDir.path, 'file_locks'));
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }

    final receivePort = ReceivePort();
    final params = _ScanParams(
      paths: validPaths,
      excludedFolders: excludedFolders,
      existingSongs: existingSongs,
      coversDirPath: coversDir.path,
      lockDirPath: lockDir.path,
      playCounts: effectivePlayCounts,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(_isolateScan, params);

    final completer = Completer<List<Song>>();
    final List<Song> allScannedSongs = [];

    receivePort.listen((message) async {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is List<Song>) {
        allScannedSongs.addAll(message);
        // Incremental DB insert
        await DatabaseService.instance.insertSongsBatch(message);
      } else if (message == 'done') {
        // Rebuild search index after scanning
        try {
          final searchService = SearchService();
          await searchService.init();
          await searchService.rebuildIndex(allScannedSongs);
          debugPrint(
              'Search index rebuilt with ${allScannedSongs.length} songs');
        } catch (e) {
          debugPrint('Error rebuilding search index: $e');
        }
        onComplete?.call(allScannedSongs);
        completer.complete(allScannedSongs);
        receivePort.close();
      } else if (message is String && message.startsWith('error:')) {
        receivePort.close();
        completer.completeError(message);
      }
    }, onError: (e) {
      receivePort.close();
      completer.completeError(e);
    });

    return completer.future;
  }

  /// Extracts cover art from a single song file using the same logic as the
  /// scanner (metadata reader → manual byte extraction → folder cover).
  /// Returns the path to the cached cover file, or null if no cover was found.
  static Future<String?> extractCoverForFile(
    File file,
    Directory coversDir,
    String hash,
    int mtimeMs, {
    bool skipFolderCover = false,
    bool useFFmpegFallback = false,
  }) async {
    if (!await file.exists()) return null;

    // Try metadata extraction first
    try {
      final metadata = amr.readMetadata(file);
      if (metadata.pictures.isNotEmpty) {
        final picture = metadata.pictures.first;
        final coverExt = _getExtFromMime(picture.mimetype);
        final coverFile =
            File(p.join(coversDir.path, '${hash}_$mtimeMs$coverExt'));
        await coverFile.writeAsBytes(picture.bytes);
        return coverFile.path;
      }
    } catch (e) {
      debugPrint('extractCoverForFile: metadata read failed: $e');
    }

    // Try manual byte-level extraction
    final manual =
        await _tryManualCoverExtraction(file, coversDir, hash, mtimeMs);
    if (manual != null) return manual;

    // (Old comment about enabling FFmpeg fallback for Main Isolate only)
    // Actually, we want to try this whenever manual extraction fails, provided we can trust FFmpegService.
    if (useFFmpegFallback) {
      try {
        // Use a unique suffix so we don't conflict with other attempts
        debugPrint(
            'Scanner: Manual extraction failed for ${file.path}, trying FFmpeg fallback...');
        final coverFile =
            File(p.join(coversDir.path, '${hash}_${mtimeMs}_ffmpeg.jpg'));
        final extracted = await FFmpegService().extractCover(
          inputPath: file.path,
          outputPath: coverFile.path,
        );
        if (extracted != null) {
          debugPrint('Scanner: FFmpeg fallback success!');
          return extracted;
        }
      } catch (e) {
        debugPrint('Scanner: FFmpeg fallback failed: $e');
      }
    }

    // Try folder cover as last resort
    if (skipFolderCover) return null;
    return _findCoverInFolder(p.dirname(file.path));
  }

  Future<Map<String, String?>> rebuildCoverCache(
    List<Song> songs, {
    void Function(double progress)? onProgress,
    bool force = false,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));

    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final lockDir = Directory(p.join(supportDir.path, 'file_locks'));
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }

    final receivePort = ReceivePort();
    await Isolate.spawn(
        _isolateRebuildCovers,
        _RebuildParams(
          songs: songs,
          coversDirPath: coversDir.path,
          lockDirPath: lockDir.path,
          sendPort: receivePort.sendPort,
          force: force,
        ));

    final completer = Completer<Map<String, String?>>();
    receivePort.listen((message) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is Map) {
        receivePort.close();
        completer.complete(Map<String, String?>.from(message));
      } else {
        receivePort.close();
        completer.completeError(message);
      }
    });

    return completer.future;
  }

  static Future<void> _isolateRebuildCovers(_RebuildParams params) async {
    final coversDir = Directory(params.coversDirPath);
    final folderCoverCache = <String, String?>{};
    final coverResults = <String, String?>{};

    for (int i = 0; i < params.songs.length; i++) {
      final song = params.songs[i];
      final file = File(song.url);
      String? resolvedCoverUrl;

      if (await file.exists()) {
        RandomAccessFile? lockHandle;
        try {
          lockHandle = await _acquireSharedLock(params.lockDirPath, file.path);
          int mtimeMs;
          if (song.mtime != null) {
            mtimeMs = (song.mtime! * 1000).round();
          } else {
            final stat = await file.stat();
            mtimeMs = stat.modified.millisecondsSinceEpoch;
          }

          final hash = md5.convert(utf8.encode(file.path)).toString();

          // Check if already exists - unless force is true
          if (!params.force) {
            for (final ext in ['.jpg', '.png', '.jpeg', '.webp', '.bmp']) {
              final cachedFile =
                  File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
              if (await cachedFile.exists()) {
                resolvedCoverUrl = cachedFile.path;
                break;
              }
            }
          }

          if (resolvedCoverUrl == null || params.force) {
            // Try metadata extraction first
            try {
              final metadata = amr.readMetadata(file);
              if (metadata.pictures.isNotEmpty) {
                final picture = metadata.pictures.first;
                final coverExt = _getExtFromMime(picture.mimetype);
                final coverFile =
                    File(p.join(coversDir.path, '${hash}_$mtimeMs$coverExt'));
                await coverFile.writeAsBytes(picture.bytes);
                resolvedCoverUrl = coverFile.path;
              }
            } catch (e) {
              debugPrint('No embedded cover found for ${song.title}: $e');
            }

            // Try manual extraction if no embedded cover found
            resolvedCoverUrl ??=
                await _tryManualCoverExtraction(file, coversDir, hash, mtimeMs);

            // Try folder cover as last resort
            if (resolvedCoverUrl == null) {
              final parentPath = p.dirname(file.path);
              if (!folderCoverCache.containsKey(parentPath)) {
                folderCoverCache[parentPath] =
                    await _findCoverInFolder(parentPath);
              }
              resolvedCoverUrl = folderCoverCache[parentPath];
            }
          }
        } catch (e) {
          debugPrint('Error rebuilding cover for ${song.title}: $e');
        } finally {
          await _releaseLock(lockHandle);
        }
      }

      coverResults[song.url] = resolvedCoverUrl;

      if (i % 10 == 0) {
        params.sendPort.send((i + 1) / params.songs.length);
      }
    }
    params.sendPort.send(coverResults);
  }

  static Future<void> _isolateScan(_ScanParams params) async {
    final coversDir = Directory(params.coversDirPath);

    // Create a lookup map for existing songs
    final Map<String, Song> existingSongsMap = params.existingSongs != null
        ? {for (var s in params.existingSongs!) s.url: s}
        : {};

    // Convert excluded folders to a set for faster lookup
    final excludedSet = params.excludedFolders.toSet();

    try {
      final List<File> audioFiles = [];

      // Scan all provided paths
      for (final scanPath in params.paths) {
        final dir = Directory(scanPath);
        if (!await dir.exists()) continue;

        try {
          await for (final entity
              in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final path = entity.path;

              // Check if file has supported extension
              if (!_supportedExtensions
                  .contains(p.extension(path).toLowerCase())) {
                continue;
              }

              // Check if path is in excluded folder
              bool isExcluded = false;
              for (final excluded in excludedSet) {
                if (p.isWithin(excluded, path) || p.equals(excluded, path)) {
                  isExcluded = true;
                  break;
                }
              }
              if (isExcluded) continue;

              audioFiles.add(entity);
            }
          }
        } catch (e) {
          debugPrint('Error scanning $scanPath: $e');
        }
      }

      final Map<String, String?> folderCoverCache = {};
      final List<Song> songs = [];

      for (int i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        final fileStat = file.statSync();
        final currentMtime = fileStat.modified.millisecondsSinceEpoch / 1000.0;

        // Check if we can reuse existing song data
        final existingSong = existingSongsMap[file.path];
        if (existingSong != null &&
            existingSong.mtime != null &&
            (existingSong.mtime! - currentMtime).abs() < 2.0) {
          final updatedPlayCount = params.playCounts[existingSong.filename] ??
              existingSong.playCount;

          songs.add(Song(
            title: existingSong.title,
            artist: existingSong.artist,
            album: existingSong.album,
            filename: existingSong.filename,
            url: existingSong.url,
            coverUrl: existingSong.coverUrl,
            hasLyrics: existingSong.hasLyrics,
            playCount: updatedPlayCount,
            duration: existingSong.duration,
            mtime: currentMtime,
          ));
        } else {
          RandomAccessFile? lockHandle;
          try {
            lockHandle =
                await _acquireSharedLock(params.lockDirPath, file.path);
            final song = await _processSingleFile(
                file, coversDir, folderCoverCache, params.playCounts,
                mtime: currentMtime);
            songs.add(song);
          } finally {
            await _releaseLock(lockHandle);
          }
        }

        if (i % 10 == 0) {
          params.sendPort.send((i + 1) / audioFiles.length);
        }

        // Send chunks of 200 songs to keep memory usage low in the isolate
        // and allow the main isolate to start processing/indexing sooner.
        if (songs.length >= 200) {
          params.sendPort.send(List<Song>.from(songs));
          songs.clear();
        }
      }

      // Send remaining songs
      if (songs.isNotEmpty) {
        params.sendPort.send(songs);
      }

      // Signal completion
      params.sendPort.send('done');
    } catch (e) {
      debugPrint('Error in scanner isolate: $e');
      params.sendPort.send('error: $e');
    }
  }

  static Future<Song> _processSingleFile(File file, Directory coversDir,
      Map<String, String?> folderCoverCache, Map<String, int> playCounts,
      {double? mtime}) async {
    final filename = p.basename(file.path);
    final parentPath = file.parent.path;
    p.extension(file.path).toLowerCase();

    String title = p.basenameWithoutExtension(file.path);
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration? duration;
    String? coverUrl;
    bool hasLyrics = false;

    // Calculate mtimeMs for cache lookup
    int mtimeMs;
    if (mtime != null) {
      mtimeMs = (mtime * 1000).round();
    } else {
      final stat = await file.stat();
      mtimeMs = stat.modified.millisecondsSinceEpoch;
    }

    final hash = md5.convert(utf8.encode(file.path)).toString();

    // Check for valid cache first (hash_mtimeMs.ext)
    for (final ext in ['.jpg', '.png', '.jpeg', '.webp', '.bmp']) {
      final cachedFile = File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
      if (await cachedFile.exists()) {
        coverUrl = cachedFile.path;
        break;
      }
    }

    try {
      final metadata = amr.readMetadata(file);
      if (metadata.title?.isNotEmpty == true) title = metadata.title!;
      if (metadata.artist?.isNotEmpty == true) artist = metadata.artist!;
      if (metadata.album?.isNotEmpty == true) album = metadata.album!;
      duration = metadata.duration;

      // Check for embedded lyrics using audio_metadata_reader
      // Note: FFmpeg is used for actual lyrics reading in the main thread
      if (metadata.lyrics?.isNotEmpty == true) {
        hasLyrics = true;
      }

      if (coverUrl == null && metadata.pictures.isNotEmpty) {
        final picture = metadata.pictures.first;
        final coverExt = _getExtFromMime(picture.mimetype);
        final coverFile =
            File(p.join(coversDir.path, '${hash}_$mtimeMs$coverExt'));

        if (!await coverFile.exists()) {
          await coverFile.writeAsBytes(picture.bytes);
        }
        coverUrl = coverFile.path;
      }
    } catch (e) {
      // Silently fail primary and move to manual
    }

    coverUrl ??=
        await _tryManualCoverExtraction(file, coversDir, hash, mtimeMs);

    if (coverUrl == null) {
      if (!folderCoverCache.containsKey(parentPath)) {
        folderCoverCache[parentPath] = await _findCoverInFolder(parentPath);
      }
      coverUrl = folderCoverCache[parentPath];
    }

    return Song(
      title: title,
      artist: artist,
      album: album,
      filename: filename,
      url: file.path,
      coverUrl: coverUrl,
      hasLyrics: hasLyrics,
      playCount: playCounts[filename] ?? 0,
      duration: duration,
      mtime:
          mtime ?? (await file.stat()).modified.millisecondsSinceEpoch / 1000.0,
    );
  }

  static Future<String?> _tryManualCoverExtraction(
      File file, Directory coversDir, String hash, int mtimeMs) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final length = await raf.length();
      // hash is passed in
      final ext = p.extension(file.path).toLowerCase();

      final bool scanEverything = length < 50 * 1024 * 1024;
      final firstScanSize = scanEverything ? length : 15 * 1024 * 1024;

      await raf.setPosition(0);
      final headerChunk = await raf.read(firstScanSize);

      if (ext == '.m4a') {
        final covrResult = await _scanForCovrBox(
            headerChunk, raf, 0, coversDir, hash, mtimeMs);
        if (covrResult != null) return covrResult;
      }

      final apicResult =
          await _scanForAPIC(headerChunk, raf, 0, coversDir, hash, mtimeMs);
      if (apicResult != null) return apicResult;

      final sigResult = await _scanBufferForSignatures(
          headerChunk, raf, 0, coversDir, hash, mtimeMs);
      if (sigResult != null) return sigResult;

      if (!scanEverything && length > firstScanSize) {
        final footerSize = (10 * 1024 * 1024).clamp(0, length - firstScanSize);
        await raf.setPosition(length - footerSize);
        final footerChunk = await raf.read(footerSize);

        final sigFooterResult = await _scanBufferForSignatures(
            footerChunk, raf, length - footerSize, coversDir, hash, mtimeMs);
        if (sigFooterResult != null) return sigFooterResult;
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  static Future<String?> _scanForAPIC(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String hash, int mtimeMs) async {
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
              subChunk, raf, offset + i, coversDir, hash, mtimeMs);
        }
      }
    }
    return null;
  }

  static Future<String?> _scanForCovrBox(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String hash, int mtimeMs) async {
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

              final coverFile =
                  File(p.join(coversDir.path, '${hash}_$mtimeMs.$type'));
              await coverFile.writeAsBytes(imgData);
              return coverFile.path;
            }
          }
        }
      }
    }
    return null;
  }

  static Future<String?> _scanBufferForSignatures(
      List<int> bytes,
      RandomAccessFile raf,
      int offset,
      Directory coversDir,
      String hash,
      int mtimeMs) async {
    for (int i = 0; i < bytes.length - 8; i++) {
      // Relaxed JPEG check: Valid JPEGs start with FF D8.
      // The byte after D8 can vary (e.g. FF E0 for JFIF, FF E1 for Exif, FF DB for DQT).
      // Strict FF D8 FF check fails for valid JPEGs embedded by FFmpeg.
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        final res = await _extractImageAt(
            raf, offset + i, 'jpg', coversDir, hash, mtimeMs);
        if (res != null) return res;
      }
      if (bytes[i] == 0x89 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x4E &&
          bytes[i + 3] == 0x47) {
        final res = await _extractImageAt(
            raf, offset + i, 'png', coversDir, hash, mtimeMs);
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
          final res = await _extractImageAt(
              raf, offset + i, 'webp', coversDir, hash, mtimeMs);
          if (res != null) return res;
        }
      }
    }
    return null;
  }

  static Future<String?> _extractImageAt(RandomAccessFile raf, int pos,
      String type, Directory coversDir, String hash, int mtimeMs) async {
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
      final coverFile = File(p.join(coversDir.path, '${hash}_$mtimeMs.$type'));
      await coverFile.writeAsBytes(data.sublist(0, actualEnd));
      return coverFile.path;
    }
    return null;
  }

  static String _getExtFromMime(String? mimeType) {
    if (mimeType == null) return '.jpg';
    final mime = mimeType.toLowerCase();
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('bmp')) return '.bmp';
    return '.jpg';
  }

  static Future<String?> _findCoverInFolder(String folderPath) async {
    final possibleNames = [
      'cover.jpg',
      'cover.png',
      'folder.jpg',
      'folder.png',
      'album.jpg',
      'album.png',
    ];
    for (final name in possibleNames) {
      final file = File(p.join(folderPath, name));
      if (await file.exists()) return file.path;
    }
    return null;
  }

  static Future<RandomAccessFile?> _acquireSharedLock(
      String lockDirPath, String filePath) async {
    try {
      final hash = md5.convert(utf8.encode(filePath)).toString();
      final lockFile = File(p.join(lockDirPath, '$hash.lock'));
      final raf = await lockFile.open(mode: FileMode.append);
      await raf.lock(FileLock.shared);
      return raf;
    } catch (e) {
      debugPrint('Scanner: failed to acquire lock for $filePath: $e');
      return null;
    }
  }

  static Future<void> _releaseLock(RandomAccessFile? raf) async {
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (_) {}
    try {
      await raf.close();
    } catch (_) {}
  }
}

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
import 'package:collection/collection.dart';
import '../models/song.dart';
import 'database_service.dart';
import '../domain/services/search_service.dart';
import 'storage_service.dart';

class _ScanParams {
  final List<String> paths;
  final List<String> excludedFolders;
  final List<Song>? existingSongs;
  final String coversDirPath;
  final List<Map<String, String>> lyricsFolders;
  final Map<String, int> playCounts;
  final SendPort sendPort;

  _ScanParams({
    required this.paths,
    required this.excludedFolders,
    this.existingSongs,
    required this.coversDirPath,
    required this.lyricsFolders,
    required this.playCounts,
    required this.sendPort,
  });
}

class _RebuildParams {
  final List<Song> songs;
  final String coversDirPath;
  final SendPort sendPort;

  _RebuildParams({
    required this.songs,
    required this.coversDirPath,
    required this.sendPort,
  });
}

class ScannerService {
  static final List<String> _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg'
  ];

  /// Scans a specific directory for audio files (backward compatibility).
  /// Note: This method respects excluded folders from settings.
  Future<List<Song>> scanDirectory(
    String path, {
    List<Song>? existingSongs,
    String? lyricsPath,
    Map<String, int>? playCounts,
    void Function(double progress)? onProgress,
    String? username,
    void Function(List<Song>)? onComplete,
  }) async {
    // Check for storage permission
    if (Platform.isAndroid) {
      var statusStorage = await Permission.storage.status;
      var statusAudio = await Permission.audio.status;

      if (!statusStorage.isGranted && !statusAudio.isGranted) {
        debugPrint('Storage permissions not granted. Cannot scan directory.');
        return [];
      }
    }

    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final storage = StorageService();
    final excludedFolders = await storage.getExcludedFolders();
    final effectivePlayCounts =
        playCounts ?? await DatabaseService.instance.getPlayCounts();

    // Convert single lyricsPath to lyricsFolders format
    final List<Map<String, String>> lyricsFolders = [];
    if (lyricsPath != null && lyricsPath.isNotEmpty) {
      lyricsFolders.add({'path': lyricsPath, 'treeUri': ''});
    }

    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final receivePort = ReceivePort();
    final params = _ScanParams(
      paths: [path],
      excludedFolders: excludedFolders,
      existingSongs: existingSongs,
      coversDirPath: coversDir.path,
      lyricsFolders: lyricsFolders,
      playCounts: effectivePlayCounts,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(_isolateScan, params);

    final completer = Completer<List<Song>>();

    receivePort.listen((message) async {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is List<Song>) {
        if (username != null) {
          try {
            final searchService = SearchService();
            await searchService.initForUser(username);
            await searchService.rebuildIndex(message);
            debugPrint('Search index rebuilt with ${message.length} songs');
          } catch (e) {
            debugPrint('Error rebuilding search index: $e');
          }
        }
        onComplete?.call(message);
        completer.complete(message);
        receivePort.close();
      } else if (message is List) {
        try {
          final songs = message.cast<Song>();
          if (username != null) {
            try {
              final searchService = SearchService();
              await searchService.initForUser(username);
              await searchService.rebuildIndex(songs);
              debugPrint('Search index rebuilt with ${songs.length} songs');
            } catch (e) {
              debugPrint('Error rebuilding search index: $e');
            }
          }
          onComplete?.call(songs);
          completer.complete(songs);
        } catch (e) {
          completer.completeError("Failed to cast result to List<Song>");
        }
        receivePort.close();
      } else {
        receivePort.close();
        completer.completeError("Unknown message from isolate: $message");
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
    String? username,
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
    final effectiveLyricsFolders =
        lyricsFolders ?? await storage.getLyricsFolders();
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

    final receivePort = ReceivePort();
    final params = _ScanParams(
      paths: validPaths,
      excludedFolders: excludedFolders,
      existingSongs: existingSongs,
      coversDirPath: coversDir.path,
      lyricsFolders: effectiveLyricsFolders,
      playCounts: effectivePlayCounts,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(_isolateScan, params);

    final completer = Completer<List<Song>>();

    receivePort.listen((message) async {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is List<Song>) {
        // Rebuild search index after scanning
        if (username != null) {
          try {
            final searchService = SearchService();
            await searchService.initForUser(username);
            await searchService.rebuildIndex(message);
            debugPrint('Search index rebuilt with ${message.length} songs');
          } catch (e) {
            debugPrint('Error rebuilding search index: $e');
          }
        }
        onComplete?.call(message);
        completer.complete(message);
        receivePort.close();
      } else if (message is List) {
        // Handle explicit typing issue if passed as dynamic list
        try {
          final songs = message.cast<Song>();
          // Rebuild search index after scanning
          if (username != null) {
            try {
              final searchService = SearchService();
              await searchService.initForUser(username);
              await searchService.rebuildIndex(songs);
              debugPrint('Search index rebuilt with ${songs.length} songs');
            } catch (e) {
              debugPrint('Error rebuilding search index: $e');
            }
          }
          onComplete?.call(songs);
          completer.complete(songs);
        } catch (e) {
          completer.completeError("Failed to cast result to List<Song>");
        }
        receivePort.close();
      } else {
        receivePort.close();
        completer.completeError("Unknown message from isolate: $message");
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

    // Try folder cover as last resort
    if (skipFolderCover) return null;
    return _findCoverInFolder(p.dirname(file.path));
  }

  Future<Map<String, String?>> rebuildCoverCache(
    List<Song> songs, {
    void Function(double progress)? onProgress,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));

    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final receivePort = ReceivePort();
    await Isolate.spawn(
        _isolateRebuildCovers,
        _RebuildParams(
          songs: songs,
          coversDirPath: coversDir.path,
          sendPort: receivePort.sendPort,
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
        try {
          int mtimeMs;
          if (song.mtime != null) {
            mtimeMs = (song.mtime! * 1000).round();
          } else {
            final stat = await file.stat();
            mtimeMs = stat.modified.millisecondsSinceEpoch;
          }

          final hash = md5.convert(utf8.encode(file.path)).toString();

          // Check if already exists - preserve existing covers to avoid overwriting manual changes
          for (final ext in ['.jpg', '.png', '.jpeg', '.webp']) {
            final cachedFile =
                File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
            if (await cachedFile.exists()) {
              resolvedCoverUrl = cachedFile.path;
              break;
            }
          }

          if (resolvedCoverUrl == null) {
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
            (existingSong.mtime! - currentMtime).abs() < 0.1) {
          final updatedPlayCount = params.playCounts[existingSong.filename] ??
              existingSong.playCount;

          songs.add(Song(
            title: existingSong.title,
            artist: existingSong.artist,
            album: existingSong.album,
            filename: existingSong.filename,
            url: existingSong.url,
            coverUrl: existingSong.coverUrl,
            lyricsUrl: existingSong.lyricsUrl,
            playCount: updatedPlayCount,
            duration: existingSong.duration,
            mtime: currentMtime,
          ));
        } else {
          final song = await _processSingleFile(file, coversDir,
              folderCoverCache, params.lyricsFolders, params.playCounts,
              mtime: currentMtime);
          songs.add(song);
        }

        if (i % 10 == 0) {
          params.sendPort.send((i + 1) / audioFiles.length);
        }
      }

      params.sendPort.send(songs);
    } catch (e) {
      debugPrint('Error in scanner isolate: $e');
      params.sendPort.send(<Song>[]);
    }
  }

  static Future<Song> _processSingleFile(
      File file,
      Directory coversDir,
      Map<String, String?> folderCoverCache,
      List<Map<String, String>> lyricsFolders,
      Map<String, int> playCounts,
      {double? mtime}) async {
    final filename = p.basename(file.path);
    final parentPath = file.parent.path;
    p.extension(file.path).toLowerCase();

    String title = p.basenameWithoutExtension(file.path);
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration? duration;
    String? coverUrl;

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
    for (final ext in ['.jpg', '.png', '.jpeg', '.webp']) {
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

    // Search for lyrics in configured lyrics folders
    String? lyricsUrl;

    // First check in song's own folder
    lyricsUrl = await _findLyricsForSong(
        p.basenameWithoutExtension(file.path), parentPath);

    // Then check in configured lyrics folders
    if (lyricsUrl == null) {
      for (final lyricsFolder in lyricsFolders) {
        final path = lyricsFolder['path'];
        if (path != null && path.isNotEmpty) {
          lyricsUrl = await _findLyricsForSong(
              p.basenameWithoutExtension(file.path), path);
          if (lyricsUrl != null) break;
        }
      }
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
    final apicSig = [0x41, 0x50, 0x49, 0x43]; // "APIC"
    int apicPos = _findBytes(bytes, apicSig);
    while (apicPos != -1) {
      final realOffset = offset + apicPos;
      final rafHeader = await raf.read(4);
      if (rafHeader.length < 4) break;

      final sizeBuffer = await raf.read(4);
      if (sizeBuffer.length < 4) break;

      final size = _readInt32BE(sizeBuffer);
      if (size <= 0 || size > 50 * 1024 * 1024) {
        final nextOffset = realOffset + 4;
        await raf.setPosition(nextOffset);
        final moreBytes = await raf.read(bytes.length);
        apicPos = _findBytes(moreBytes, apicSig);
        continue;
      }

      final data = await raf.read(size);
      if (data.length < size) break;

      final mimeTypeEnd = data.indexOf(0);
      if (mimeTypeEnd > 0 && mimeTypeEnd < 100) {
        final mimeType = String.fromCharCodes(data.sublist(0, mimeTypeEnd));
        final mimeExtMap = {
          'image/jpeg': '.jpg',
          'image/png': '.png',
          'image/webp': '.webp',
          'image/bmp': '.bmp',
        };
        final ext = mimeExtMap[mimeType] ?? '.jpg';

        // Skip picture type and description to get image data
        int imgStart = mimeTypeEnd + 1;
        if (imgStart < data.length) imgStart++; // Skip picture type
        while (imgStart < data.length && data[imgStart] != 0) imgStart++;
        if (imgStart < data.length) imgStart++; // Skip null terminator

        if (imgStart < data.length && data.length - imgStart > 100) {
          final extToSig = {
            '.jpg': [0xFF, 0xD8],
            '.png': [0x89, 0x50],
            '.webp': [0x52, 0x49],
          };
          final expectedSig = extToSig[ext] ?? [];
          final actualSig = data.sublist(imgStart, imgStart + 2);

          if (ListEquality().equals(expectedSig, actualSig)) {
            final coverFile =
                File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
            await coverFile.writeAsBytes(data.sublist(imgStart));
            return coverFile.path;
          }
        }
      }

      // Continue searching
      final nextOffset = realOffset + 4;
      await raf.setPosition(nextOffset);
      final moreBytes = await raf.read(bytes.length);
      apicPos = _findBytes(moreBytes, apicSig);
    }
    return null;
  }

  static Future<String?> _scanForCovrBox(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String hash, int mtimeMs) async {
    int pos = 0;
    while (pos < bytes.length - 8) {
      final size = _readInt32BE(bytes.sublist(pos, pos + 4));
      final typeStr = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));

      if (typeStr == 'covr' && size > 8 && size < 50 * 1024 * 1024) {
        final dataOffset = pos + 8;
        if (dataOffset + size - 8 <= bytes.length) {
          final coverData = bytes.sublist(dataOffset, dataOffset + size - 8);
          final ext = _detectImageFormat(coverData);
          if (ext != null) {
            final coverFile =
                File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
            await coverFile.writeAsBytes(coverData);
            return coverFile.path;
          }
        }
        return null;
      }

      if (size < 8) break;
      pos += size;
    }
    return null;
  }

  static String? _detectImageFormat(List<int> data) {
    if (data.length < 4) return null;
    final header = data.sublist(0, 4);

    if (header[0] == 0xFF && header[1] == 0xD8) return '.jpg';
    if (header[0] == 0x89 && header[1] == 0x50) return '.png';
    if (header[0] == 0x52 && header[1] == 0x49) return '.webp';
    if (header[0] == 0x42 && header[1] == 0x4D) return '.bmp';

    return null;
  }

  static Future<String?> _scanBufferForSignatures(
      List<int> bytes,
      RandomAccessFile raf,
      int offset,
      Directory coversDir,
      String hash,
      int mtimeMs) async {
    final signatures = {
      '.jpg': [0xFF, 0xD8, 0xFF],
      '.png': [0x89, 0x50, 0x4E, 0x47],
      '.webp': [0x52, 0x49, 0x46, 0x46],
    };

    for (final entry in signatures.entries) {
      final ext = entry.key;
      final sig = entry.value;
      int pos = _findBytes(bytes, sig);

      if (pos != -1) {
        final realOffset = offset + pos;
        int? endPos = _findBytes(bytes.sublist(pos + sig.length), [0xFF, 0xD9]);

        if (endPos == -1 && ext == '.jpg') {
          await raf.setPosition(realOffset);
          final moreData = await raf.read(10 * 1024 * 1024);
          endPos = _findBytes(moreData, [0xFF, 0xD9]);
          if (endPos != -1) {
            endPos += sig.length + moreData.length;
          }
        }

        if (endPos != -1 && endPos > sig.length + 100) {
          final coverFile =
              File(p.join(coversDir.path, '${hash}_$mtimeMs$ext'));
          await coverFile.writeAsBytes(bytes.sublist(pos, pos + endPos + 2));
          return coverFile.path;
        }
      }
    }
    return null;
  }

  static int _findBytes(List<int> bytes, List<int> pattern) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;
    for (int i = 0; i <= bytes.length - pattern.length; i++) {
      bool found = true;
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  static int _readInt32BE(List<int> bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  static String _getExtFromMime(String? mimeType) {
    switch (mimeType?.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/bmp':
        return '.bmp';
      default:
        return '.jpg';
    }
  }

  static Future<String?> _findCoverInFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final coverNames = [
      'cover.jpg',
      'cover.png',
      'folder.jpg',
      'folder.png',
      'album.jpg',
      'album.png',
      'front.jpg',
      'front.png',
    ];

    for (final name in coverNames) {
      final file = File(p.join(folderPath, name));
      if (await file.exists()) {
        return file.path;
      }
    }

    return null;
  }

  static Future<String?> _findLyricsForSong(
      String songName, String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final extensions = ['.lrc', '.txt'];

    for (final ext in extensions) {
      final file = File(p.join(folderPath, '$songName$ext'));
      if (await file.exists()) {
        return file.path;
      }
    }

    return null;
  }
}

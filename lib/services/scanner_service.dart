import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'database_service.dart';
import '../domain/services/search_service.dart';
import 'storage_service.dart';
import 'ffmpeg_service.dart';

/// Why a scan produced the songs it did.
///
/// The distinction matters because an empty song list is ambiguous: it can mean
/// "the folder really is empty" or "we could not look inside it". Only the
/// former may replace an existing library — see [shouldReplaceLibrary].
enum ScanStatus {
  /// Every requested folder was listed successfully.
  ok,

  /// Storage permission was not granted, so nothing was listed.
  noPermission,

  /// A folder is missing, unmounted, or failed to list.
  folderUnavailable,
}

class ScanResult {
  final List<Song> songs;
  final ScanStatus status;

  const ScanResult(this.songs, this.status);

  const ScanResult.ok(this.songs) : status = ScanStatus.ok;

  const ScanResult.failed(this.status) : songs = const [];

  bool get trusted => status == ScanStatus.ok;
}

class _ScanParams {
  final List<String> paths;
  final List<String> excludedFolders;
  final List<Song>? existingSongs;
  final String coversDirPath;
  final String lockDirPath;
  final Map<String, int> playCounts;
  final SendPort sendPort;
  final bool includeVideos;
  final int minimumFileSizeBytes;
  final bool fastMode;

  _ScanParams({
    required this.paths,
    required this.excludedFolders,
    this.existingSongs,
    required this.coversDirPath,
    required this.lockDirPath,
    required this.playCounts,
    required this.sendPort,
    this.includeVideos = true,
    this.minimumFileSizeBytes = 0,
    this.fastMode = false,
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

/// Result of enriching one batch: every song in the batch (enriched or not),
/// plus just the ones that actually changed and need a DB write.
class _EnrichResult {
  final List<Song> songs;
  final List<Song> changed;

  _EnrichResult(this.songs, this.changed);
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
    '.opus',
    '.m4v',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
    '.3gp',
  ];

  static bool _isVideoFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return Song.videoExtensions.contains(ext);
  }

  static Future<bool> _isValidCoverFile(
    File file, {
    bool requireDecodable = false,
  }) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() <= 0) return false;
      if (!requireDecodable) return true;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;
      final decoded = img.decodeImage(bytes);
      return decoded != null && decoded.width > 0 && decoded.height > 0;
    } catch (_) {
      return false;
    }
  }

  /// Extracts video thumbnails (via FFmpeg frame grab) for any video-format
  /// songs that still have no cover art. This must be called on the main thread
  /// after scanning because FFmpegService uses platform channels.
  ///
  /// Returns a new list of [Song] objects with updated [coverUrl] values.
  /// Songs that already have a cover (or are not video files) are returned
  /// unchanged. [onProgress] receives values in [0, 1].
  Future<List<Song>> postProcessVideoThumbnails(
    List<Song> songs, {
    void Function(double progress)? onProgress,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    // Only process video songs that are missing a cover.
    final toProcess = <int>[];
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      if (!_isVideoFile(song.url)) continue;
      final file = File(song.url);
      if (!await file.exists()) continue;

      final hash = coverKeyForFilename(file.path);

      final existingCoverPath = song.coverUrl;
      if (existingCoverPath != null && existingCoverPath.isNotEmpty) {
        final existing = File(existingCoverPath);
        final isSongScopedCachedCover =
            p.basename(existingCoverPath).startsWith(hash);
        if (isSongScopedCachedCover &&
            await _isValidCoverFile(existing, requireDecodable: true)) {
          continue;
        }
      }
      toProcess.add(i);
    }

    if (toProcess.isEmpty) return songs;

    final updated = List<Song>.from(songs);
    final ffmpeg = FFmpegService();

    for (int j = 0; j < toProcess.length; j++) {
      final idx = toProcess[j];
      final song = updated[idx];
      try {
        final file = File(song.url);
        if (!await file.exists()) continue;

        final hash = coverKeyForFilename(file.path);

        // Check if a cached cover already exists (may have been created by a
        // parallel path we aren't aware of).
        String? existing;
        for (final ext in [
          '.jpg',
          '.png',
          '.jpeg',
          '.webp',
          '.bmp',
          '_ffmpeg.jpg'
        ]) {
          final candidate = File(p.join(coversDir.path, '$hash$ext'));
          if (await _isValidCoverFile(candidate, requireDecodable: true)) {
            existing = candidate.path;
            break;
          }
        }

        if (existing != null) {
          updated[idx] = _songWithCover(song, existing);
        } else {
          final outputPath = p.join(coversDir.path, '${hash}_ffmpeg.jpg');
          // Use extractVideoThumbnail — NOT extractCover.
          // extractCover does a stream-copy of 0:v:0 which works for audio
          // files whose video stream is an attached picture, but for real
          // video files that stream is H.264/VP9/etc. and cannot be copied
          // into a JPEG. extractVideoThumbnail grabs the 5th decoded frame
          // instead.
          final result = await _extractVideoThumbnailWithFallback(
            inputPath: file.path,
            outputPath: outputPath,
            ffmpeg: ffmpeg,
          );
          if (result != null) {
            updated[idx] = _songWithCover(song, result);
            debugPrint(
                'postProcessVideoThumbnails: extracted thumbnail for ${song.title}');
          }
        }
      } catch (e) {
        debugPrint('postProcessVideoThumbnails: failed for ${song.title}: $e');
      }

      onProgress?.call((j + 1) / toProcess.length);
    }

    return updated;
  }

  static Song _songWithCover(Song song, String coverPath) {
    return Song(
      title: song.title,
      artist: song.artist,
      album: song.album,
      filename: song.filename,
      url: song.url,
      coverUrl: coverPath,
      hasLyrics: song.hasLyrics,
      playCount: song.playCount,
      duration: song.duration,
      mtime: song.mtime,
      createdEpochSec: song.createdEpochSec,
      songDateEpochSec: song.songDateEpochSec,
    );
  }

  /// Scans a specific directory for audio files (backward compatibility).
  Future<ScanResult> scanDirectory(
    String path, {
    List<Song>? existingSongs,
    String? lyricsPath,
    Map<String, int>? playCounts,
    void Function(double progress)? onProgress,
    void Function(List<Song>)? onComplete,
    bool includeVideos = true,
    int minimumFileSizeBytes = 0,
    bool fastMode = false,
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
          return const ScanResult.failed(ScanStatus.noPermission);
        }
      }
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('Music folder unavailable: $path');
      return const ScanResult.failed(ScanStatus.folderUnavailable);
    }

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
      includeVideos: includeVideos,
      minimumFileSizeBytes: minimumFileSizeBytes,
      fastMode: fastMode,
    );

    await Isolate.spawn(_isolateScan, params);

    final completer = Completer<ScanResult>();
    final List<Song> allScannedSongs = [];
    // Set if the isolate reports a folder it could not list. A single
    // unreachable folder taints the whole scan so its empty result can never
    // clobber an existing library.
    bool folderUnavailable = false;

    receivePort.listen((message) async {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is List<Song>) {
        allScannedSongs.addAll(message);
        // Incremental DB insert to save memory and keep UI responsive
        await DatabaseService.instance.insertSongsBatch(message);
      } else if (message is String && message.startsWith('unreachable:')) {
        folderUnavailable = true;
      } else if (message == 'done') {
        final status =
            folderUnavailable ? ScanStatus.folderUnavailable : ScanStatus.ok;
        if (!fastMode) {
          try {
            final searchService = SearchService();
            await searchService.init();
            await searchService.rebuildIndex(allScannedSongs);
            debugPrint(
                'Search index rebuilt with ${allScannedSongs.length} songs');
          } catch (e) {
            debugPrint('Error rebuilding search index: $e');
          }
          // Extract thumbnails for video files on the main thread using FFmpeg.
          // This must happen here (not in the isolate) because FFmpegService
          // uses platform channels.
          List<Song> finalSongs = allScannedSongs;
          try {
            finalSongs = await postProcessVideoThumbnails(allScannedSongs);
            // Persist any newly-extracted cover URLs back to the DB.
            final updated = <Song>[];
            for (int i = 0; i < finalSongs.length; i++) {
              if (finalSongs[i].coverUrl != allScannedSongs[i].coverUrl) {
                updated.add(finalSongs[i]);
              }
            }
            if (updated.isNotEmpty) {
              await DatabaseService.instance.insertSongsBatch(updated);
              debugPrint(
                  'Video thumbnails extracted for ${updated.length} songs');
            }
          } catch (e) {
            debugPrint('Error post-processing video thumbnails: $e');
            finalSongs = allScannedSongs;
          }
          onComplete?.call(finalSongs);
          completer.complete(ScanResult(finalSongs, status));
        } else {
          onComplete?.call(allScannedSongs);
          completer.complete(ScanResult(allScannedSongs, status));
        }
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
    bool fastMode = false,
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
      fastMode: fastMode,
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
        if (!fastMode) {
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
          // Extract thumbnails for video files on the main thread using FFmpeg.
          List<Song> finalSongs = allScannedSongs;
          try {
            finalSongs = await postProcessVideoThumbnails(allScannedSongs);
            final updated = <Song>[];
            for (int i = 0; i < finalSongs.length; i++) {
              if (finalSongs[i].coverUrl != allScannedSongs[i].coverUrl) {
                updated.add(finalSongs[i]);
              }
            }
            if (updated.isNotEmpty) {
              await DatabaseService.instance.insertSongsBatch(updated);
              debugPrint(
                  'Video thumbnails extracted for ${updated.length} songs');
            }
          } catch (e) {
            debugPrint('Error post-processing video thumbnails: $e');
            finalSongs = allScannedSongs;
          }
          onComplete?.call(finalSongs);
          completer.complete(finalSongs);
        } else {
          onComplete?.call(allScannedSongs);
          completer.complete(allScannedSongs);
        }
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

  /// Enriches minimal song records with metadata (title, artist, album, duration).
  ///
  /// [amr.readMetadata] is fully synchronous, so parsing runs in a background
  /// isolate one batch at a time — on the main isolate it would block the UI
  /// thread for the entire library. Only the DB write and progress callback
  /// stay here, since sqflite is not usable from a spawned isolate.
  static Future<List<Song>> enrichAllMetadata(
    List<Song> songs, {
    void Function(double progress)? onProgress,
  }) async {
    final updated = <Song>[];
    final total = songs.length;
    const batchSize = 50;

    for (int i = 0; i < total; i += batchSize) {
      final end = (i + batchSize).clamp(0, total);
      final batch = songs.sublist(i, end);

      final result = await Isolate.run(() => _enrichBatch(batch));

      updated.addAll(result.songs);

      if (result.changed.isNotEmpty) {
        await DatabaseService.instance.insertSongsBatch(result.changed);
      }

      onProgress?.call(end / total);
    }

    return updated;
  }

  /// Parses one batch of songs. Runs inside a background isolate — must not
  /// touch DatabaseService or any plugin.
  static Future<_EnrichResult> _enrichBatch(List<Song> batch) async {
    final songs = <Song>[];
    final changed = <Song>[];

    for (final song in batch) {
      final file = File(song.url);
      if (!await file.exists()) {
        songs.add(song);
        continue;
      }

      // Only process records the fast scan left untouched. Testing the fields
      // with || instead re-parses every song whose file simply has no album
      // tag, on every single scan.
      final isUnenriched =
          song.title == p.basenameWithoutExtension(file.path) &&
              song.artist == 'Unknown Artist' &&
              song.album == 'Unknown Album';
      if (!isUnenriched) {
        songs.add(song);
        continue;
      }

      // Skip video files — audio_metadata_reader can crash on video
      // containers like MKV, WebM, AVI. Video metadata (title from
      // filename) is already populated by the fast scan.
      if (_isVideoFile(file.path)) {
        songs.add(song);
        continue;
      }

      try {
        final metadata = amr.readMetadata(file);
        String title = song.title;
        String artist = song.artist;
        String album = song.album;
        Duration? duration = song.duration;
        bool hasLyrics = song.hasLyrics;
        double? songDateEpochSec = song.songDateEpochSec;

        if (metadata.title?.isNotEmpty == true) title = metadata.title!;
        if (metadata.artist?.isNotEmpty == true) artist = metadata.artist!;
        if (metadata.album?.isNotEmpty == true) album = metadata.album!;
        if (metadata.year != null) {
          songDateEpochSec =
              metadata.year!.millisecondsSinceEpoch.toDouble() / 1000.0;
        }
        duration = metadata.duration;
        if (metadata.lyrics?.isNotEmpty == true) {
          hasLyrics = true;
        }

        final enriched = Song(
          title: title,
          artist: artist,
          album: album,
          filename: song.filename,
          url: song.url,
          coverUrl: song.coverUrl,
          hasLyrics: hasLyrics,
          playCount: song.playCount,
          duration: duration,
          mtime: song.mtime,
          createdEpochSec: song.createdEpochSec,
          songDateEpochSec: songDateEpochSec,
        );
        changed.add(enriched);
        songs.add(enriched);
      } catch (_) {
        songs.add(song);
      }
    }

    return _EnrichResult(songs, changed);
  }

  /// Extracts cover art for a single song on demand.
  /// Used for lazy cover extraction — only called when a song's cover is
  /// first viewed. Avoids the cost of extracting every cover during scanning.
  static Future<String?> extractCoverOnDemand(Song song) async {
    final file = File(song.url);
    if (!await file.exists()) return null;

    final isVideo = _isVideoFile(song.url);
    final supportDir = await getApplicationSupportDirectory();
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    return await extractCoverForFile(
      file,
      coversDir,
      p.basename(file.path),
      useFFmpegFallback: isVideo,
    );
  }

  /// The pure-Dart half of cover extraction: embedded picture → folder cover →
  /// manual byte scan. Uses no platform channels, so it is safe to run inside
  /// [Isolate.run] — the byte scan can read the whole audio file and must never
  /// happen on the UI thread.
  ///
  /// Returns null when only the FFmpeg fallback could still succeed.
  static Future<String?> extractCoverWithoutFFmpeg(
    String filePath,
    String coversDirPath,
    String filename, {
    bool skipFolderCover = false,
  }) async {
    final file = File(filePath);
    if (_isVideoFile(filePath)) return null;
    if (!await file.exists()) return null;

    final coversDir = Directory(coversDirPath);
    final hash = coverKeyForFilename(filename);

    try {
      // getImage: true is required — the parser skips picture frames
      // otherwise, and this whole cheap path silently never fires.
      final metadata = amr.readMetadata(file, getImage: true);
      if (metadata.pictures.isNotEmpty) {
        final picture = metadata.pictures.first;
        final coverExt = _getExtFromMime(picture.mimetype);
        final coverFile = File(p.join(coversDir.path, '$hash$coverExt'));
        await coverFile.writeAsBytes(picture.bytes);
        return coverFile.path;
      }
    } catch (e) {
      debugPrint('extractCoverWithoutFFmpeg: metadata read failed: $e');
    }

    // Folder cover before the manual byte scan — a handful of exists()
    // checks is far cheaper than reading the whole audio file.
    if (!skipFolderCover) {
      final folderCover = await _findCoverInFolder(p.dirname(filePath));
      if (folderCover != null) return folderCover;
    }

    return await _tryManualCoverExtraction(file, coversDir, filename);
  }

  /// Extracts cover art from a single song file using the same logic as the
  /// scanner (metadata reader → folder cover → manual byte extraction →
  /// FFmpeg). Returns the path to the cached cover file, or null if no cover
  /// was found.
  static Future<String?> extractCoverForFile(
    File file,
    Directory coversDir,
    String filename, {
    bool skipFolderCover = false,
    bool useFFmpegFallback = false,
  }) async {
    if (!await file.exists()) return null;
    final isVideo = _isVideoFile(file.path);

    final pureDart = await extractCoverWithoutFFmpeg(
      file.path,
      coversDir.path,
      filename,
      skipFolderCover: skipFolderCover,
    );
    if (pureDart != null) return pureDart;

    if (useFFmpegFallback || isVideo) {
      final viaFFmpeg = await extractCoverWithFFmpeg(file, coversDir, filename);
      if (viaFFmpeg != null) return viaFFmpeg;
    }

    // extractCoverWithoutFFmpeg bails out immediately on video files, so they
    // still need a folder-cover fallback once FFmpeg has failed.
    if (isVideo && !skipFolderCover) {
      return _findCoverInFolder(p.dirname(file.path));
    }

    return null;
  }

  /// The FFmpeg half of cover extraction. Uses platform channels, so it must
  /// run on the main isolate. Call only after [extractCoverWithoutFFmpeg] has
  /// come up empty — an FFmpeg invocation per song is expensive.
  static Future<String?> extractCoverWithFFmpeg(
    File file,
    Directory coversDir,
    String filename,
  ) async {
    final hash = coverKeyForFilename(filename);
    try {
      debugPrint(
          'Scanner: Manual extraction failed for ${file.path}, trying FFmpeg fallback...');
      final coverFile = File(p.join(coversDir.path, '${hash}_ffmpeg.jpg'));

      String? extracted;
      if (_isVideoFile(file.path)) {
        extracted = await _extractVideoThumbnailWithFallback(
          inputPath: file.path,
          outputPath: coverFile.path,
        );
      } else {
        extracted = await FFmpegService().extractCover(
          inputPath: file.path,
          outputPath: coverFile.path,
        );
      }

      if (extracted != null) {
        debugPrint('Scanner: FFmpeg fallback success!');
        return extracted;
      }
    } catch (e) {
      debugPrint('Scanner: FFmpeg fallback failed: $e');
    }
    return null;
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

    // Separate video files from audio files - video thumbnails must be extracted
    // on the main thread via FFmpeg (platform channels don't work in isolates).
    final videoSongs = <Song>[];
    final otherSongs = <Song>[];
    for (final song in songs) {
      if (_isVideoFile(song.url)) {
        videoSongs.add(song);
      } else {
        otherSongs.add(song);
      }
    }

    // Process audio files in isolate (fast)
    final coverResults = <String, String?>{};
    if (otherSongs.isNotEmpty) {
      final receivePort = ReceivePort();
      await Isolate.spawn(
          _isolateRebuildCovers,
          _RebuildParams(
            songs: otherSongs,
            coversDirPath: coversDir.path,
            lockDirPath: lockDir.path,
            sendPort: receivePort.sendPort,
            force: force,
          ));

      final completer = Completer<Map<String, String?>>();
      receivePort.listen((message) {
        if (message is double) {
          onProgress?.call(message * 0.7); // Audio files get 70% of progress
        } else if (message is Map) {
          receivePort.close();
          completer.complete(Map<String, String?>.from(message));
        } else {
          receivePort.close();
          completer.completeError(message);
        }
      });

      final audioResults = await completer.future;
      coverResults.addAll(audioResults);
    }

    // Process video files on main thread via FFmpeg (required for frame extraction)
    if (videoSongs.isNotEmpty) {
      final ffmpeg = FFmpegService();
      for (int i = 0; i < videoSongs.length; i++) {
        final song = videoSongs[i];
        onProgress
            ?.call(0.7 + (i / videoSongs.length) * 0.3); // Video files get 30%

        final file = File(song.url);
        if (!await file.exists()) continue;

        final hash = coverKeyForFilename(file.path);

        // Check existing cache first
        String? existing;
        for (final ext in [
          '.jpg',
          '.png',
          '.jpeg',
          '.webp',
          '.bmp',
          '_ffmpeg.jpg'
        ]) {
          final candidate = File(p.join(coversDir.path, '$hash$ext'));
          if (await _isValidCoverFile(candidate, requireDecodable: true)) {
            existing = candidate.path;
            break;
          }
        }

        if (existing != null && !force) {
          coverResults[song.url] = existing;
        } else {
          final outputPath = p.join(coversDir.path, '${hash}_ffmpeg.jpg');
          final result = await _extractVideoThumbnailWithFallback(
            inputPath: file.path,
            outputPath: outputPath,
            ffmpeg: ffmpeg,
          );
          coverResults[song.url] = result;
        }
      }
    }

    return coverResults;
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
          final hash = coverKeyForFilename(file.path);

          // Check if already exists - unless force is true
          if (!params.force) {
            for (final ext in ['.jpg', '.png', '.jpeg', '.webp', '.bmp']) {
              final cachedFile = File(p.join(coversDir.path, '$hash$ext'));
              if (await _isValidCoverFile(cachedFile)) {
                resolvedCoverUrl = cachedFile.path;
                break;
              }
            }
          }

          if (resolvedCoverUrl == null || params.force) {
            if (!_isVideoFile(file.path)) {
              try {
                final metadata = amr.readMetadata(file, getImage: true);
                if (metadata.pictures.isNotEmpty) {
                  final picture = metadata.pictures.first;
                  final coverExt = _getExtFromMime(picture.mimetype);
                  final coverFile =
                      File(p.join(coversDir.path, '$hash$coverExt'));
                  await coverFile.writeAsBytes(picture.bytes);
                  resolvedCoverUrl = coverFile.path;
                }
              } catch (e) {
                debugPrint('No embedded cover found for ${song.title}: $e');
              }
            }

            // Folder cover before the manual byte scan — cheap exists()
            // checks beat reading the whole audio file.
            if (resolvedCoverUrl == null) {
              final parentPath = p.dirname(file.path);
              if (!folderCoverCache.containsKey(parentPath)) {
                folderCoverCache[parentPath] =
                    await _findCoverInFolder(parentPath);
              }
              resolvedCoverUrl = folderCoverCache[parentPath];
            }

            resolvedCoverUrl ??= await _tryManualCoverExtraction(
                file, coversDir, p.basename(file.path));
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

  static Future<String?> _extractVideoThumbnailWithFallback({
    required String inputPath,
    required String outputPath,
    FFmpegService? ffmpeg,
  }) async {
    final service = ffmpeg ?? FFmpegService();
    final ffmpegResult = await service.extractVideoThumbnail(
      inputPath: inputPath,
      outputPath: outputPath,
    );
    if (ffmpegResult != null &&
        await _isValidCoverFile(File(ffmpegResult), requireDecodable: true)) {
      return ffmpegResult;
    }
    return null;
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
        if (!await dir.exists()) {
          // Report rather than silently yielding zero songs for this folder —
          // the caller needs to tell "empty" apart from "couldn't look".
          params.sendPort.send('unreachable:$scanPath');
          continue;
        }

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

              // Skip video files if includeVideos is off
              if (!params.includeVideos &&
                  Song.videoExtensions
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
          // A transient IO/permission error mid-listing is not "empty folder".
          params.sendPort.send('unreachable:$scanPath');
        }
      }

      final Map<String, String?> folderCoverCache = {};
      final List<Song> songs = [];
      int processedCount = 0;

      for (int i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        final fileStat = file.statSync();
        final currentMtime = fileStat.modified.millisecondsSinceEpoch / 1000.0;

        // Skip files below minimum size
        if (params.minimumFileSizeBytes > 0 &&
            fileStat.size < params.minimumFileSizeBytes) {
          if (i % 10 == 0) {
            params.sendPort.send((i + 1) / audioFiles.length);
          }
          continue;
        }

        // Check if we can reuse existing song data
        final existingSong = existingSongsMap[file.path];
        if (existingSong != null &&
            existingSong.mtime != null &&
            (existingSong.mtime! - currentMtime).abs() < 2.0) {
          final updatedPlayCount = params.playCounts[existingSong.filename] ??
              existingSong.playCount;
          final createdEpochSec = existingSong.createdEpochSec ??
              DateTime.now().millisecondsSinceEpoch / 1000.0;

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
            createdEpochSec: createdEpochSec,
            songDateEpochSec: existingSong.songDateEpochSec,
          ));
        } else if (params.fastMode) {
          songs.add(Song(
            title: p.basenameWithoutExtension(file.path),
            artist: 'Unknown Artist',
            album: 'Unknown Album',
            filename: p.basename(file.path),
            url: file.path,
            coverUrl: null,
            hasLyrics: false,
            playCount: 0,
            duration: null,
            mtime: currentMtime,
            createdEpochSec: DateTime.now().millisecondsSinceEpoch / 1000.0,
            songDateEpochSec: null,
          ));
        } else {
          RandomAccessFile? lockHandle;
          try {
            lockHandle =
                await _acquireSharedLock(params.lockDirPath, file.path);
            final song = await _processSingleFile(
                file, coversDir, folderCoverCache, params.playCounts,
                mtime: currentMtime, existingSong: existingSong);
            songs.add(song);
          } finally {
            await _releaseLock(lockHandle);
          }
        }

        // Yield CPU every 20 files to avoid starving the system
        processedCount++;
        if (processedCount % 20 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
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
      {double? mtime, Song? existingSong}) async {
    final filename = p.basename(file.path);
    final parentPath = file.parent.path;
    p.extension(file.path).toLowerCase();

    String title = p.basenameWithoutExtension(file.path);
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    Duration? duration;
    String? coverUrl;
    bool hasLyrics = false;
    double? songDateEpochSec;
    final fileStat = await file.stat();
    final createdEpochSec = existingSong?.createdEpochSec ??
        DateTime.now().millisecondsSinceEpoch / 1000.0;
    final isVideo = _isVideoFile(file.path);

    final hash = coverKeyForFilename(filename);

    // Check for valid cache first
    for (final ext in ['.jpg', '.png', '.jpeg', '.webp', '.bmp']) {
      final cachedFile = File(p.join(coversDir.path, '$hash$ext'));
      if (await _isValidCoverFile(cachedFile, requireDecodable: isVideo)) {
        coverUrl = cachedFile.path;
        break;
      }
    }

    if (!isVideo) {
      // Only use audio_metadata_reader for non-video files — it can crash or
      // hang on large video containers (MKV, WebM, AVI, etc.).
      try {
        final metadata = amr.readMetadata(file, getImage: coverUrl == null);
        if (metadata.title?.isNotEmpty == true) title = metadata.title!;
        if (metadata.artist?.isNotEmpty == true) artist = metadata.artist!;
        if (metadata.album?.isNotEmpty == true) album = metadata.album!;
        if (metadata.year != null) {
          songDateEpochSec =
              metadata.year!.millisecondsSinceEpoch.toDouble() / 1000.0;
        } else {
          songDateEpochSec = existingSong?.songDateEpochSec;
        }
        duration = metadata.duration;

        // Check for embedded lyrics using audio_metadata_reader
        // Note: FFmpeg is used for actual lyrics reading in the main thread
        if (metadata.lyrics?.isNotEmpty == true) {
          hasLyrics = true;
        }

        if (coverUrl == null && metadata.pictures.isNotEmpty) {
          final picture = metadata.pictures.first;
          final coverExt = _getExtFromMime(picture.mimetype);
          final coverFile = File(p.join(coversDir.path, '$hash$coverExt'));

          if (!await coverFile.exists()) {
            await coverFile.writeAsBytes(picture.bytes);
          }
          coverUrl = coverFile.path;
        }
      } catch (e) {
        // Silently fail primary and move to manual
      }
    }

    // Folder cover before the manual byte scan — cheap exists() checks beat
    // reading the whole audio file.
    if (coverUrl == null) {
      if (!folderCoverCache.containsKey(parentPath)) {
        folderCoverCache[parentPath] = await _findCoverInFolder(parentPath);
      }
      coverUrl = folderCoverCache[parentPath];
    }

    // Manual byte-level extraction is only used for audio files.
    // Video files are handled later by postProcessVideoThumbnails on the main
    // thread via FFmpeg frame extraction to avoid false-positive embedded data.
    if (!isVideo) {
      coverUrl ??= await _tryManualCoverExtraction(file, coversDir, filename);
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
      mtime: mtime ?? fileStat.modified.millisecondsSinceEpoch / 1000.0,
      createdEpochSec: createdEpochSec,
      songDateEpochSec: songDateEpochSec,
    );
  }

  static Future<String?> _tryManualCoverExtraction(
      File file, Directory coversDir, String filename) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final length = await raf.length();
      final ext = p.extension(file.path).toLowerCase();

      final bool scanEverything = length < 50 * 1024 * 1024;
      final firstScanSize = scanEverything ? length : 15 * 1024 * 1024;

      await raf.setPosition(0);
      final headerChunk = await raf.read(firstScanSize);

      if (ext == '.m4a') {
        final covrResult =
            await _scanForCovrBox(headerChunk, raf, 0, coversDir, filename);
        if (covrResult != null) return covrResult;
      }

      final apicResult =
          await _scanForAPIC(headerChunk, raf, 0, coversDir, filename);
      if (apicResult != null) return apicResult;

      final sigResult = await _scanBufferForSignatures(
          headerChunk, raf, 0, coversDir, filename);
      if (sigResult != null) return sigResult;

      if (!scanEverything && length > firstScanSize) {
        final footerSize = (10 * 1024 * 1024).clamp(0, length - firstScanSize);
        await raf.setPosition(length - footerSize);
        final footerChunk = await raf.read(footerSize);

        final sigFooterResult = await _scanBufferForSignatures(
            footerChunk, raf, length - footerSize, coversDir, filename);
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
      int offset, Directory coversDir, String filename) async {
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
              subChunk, raf, offset + i, coversDir, filename);
        }
      }
    }
    return null;
  }

  static Future<String?> _scanForCovrBox(List<int> bytes, RandomAccessFile raf,
      int offset, Directory coversDir, String filename) async {
    final hash = coverKeyForFilename(filename);
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

  static Future<String?> _scanBufferForSignatures(
      List<int> bytes,
      RandomAccessFile raf,
      int offset,
      Directory coversDir,
      String filename) async {
    for (int i = 0; i < bytes.length - 8; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        final res =
            await _extractImageAt(raf, offset + i, 'jpg', coversDir, filename);
        if (res != null) return res;
      }
      if (bytes[i] == 0x89 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x4E &&
          bytes[i + 3] == 0x47) {
        final res =
            await _extractImageAt(raf, offset + i, 'png', coversDir, filename);
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
              raf, offset + i, 'webp', coversDir, filename);
          if (res != null) return res;
        }
      }
    }
    return null;
  }

  static Future<String?> _extractImageAt(RandomAccessFile raf, int pos,
      String type, Directory coversDir, String filename) async {
    final hash = coverKeyForFilename(filename);
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

  static String coverKeyForFilename(String filename) {
    return sha1.convert(utf8.encode(p.basename(filename))).toString();
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

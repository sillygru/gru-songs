import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'database_service.dart';
import 'scanner_service.dart';

/// Fills in missing cover art for songs, on demand.
///
/// After a fast-mode scan every song has a null coverUrl, so every list tile
/// that comes on screen asks for one at once. Extraction is expensive — it can
/// read the entire audio file and shell out to FFmpeg — so this service caps
/// how much of it runs at a time, keeps the heavy part off the UI thread, and
/// remembers songs that have no art so they are never probed twice.
class CoverRefreshService {
  static final CoverRefreshService instance = CoverRefreshService._internal();

  CoverRefreshService._internal();

  /// Extraction is I/O- and CPU-heavy; more than a couple at a time on a
  /// budget phone just starves the UI thread without finishing any sooner.
  static const int _maxConcurrent = 2;

  final Set<String> _inFlight = {};
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _active = 0;

  /// filename -> file mtime at the time we found no cover.
  Map<String, double>? _misses;
  Future<Map<String, double>>? _missesLoad;

  /// Whether [ensureCoverForSong] is known to be pointless for this song, so
  /// callers can skip scheduling it at all. Only reflects misses already
  /// loaded — it never blocks.
  bool isKnownMiss(String songFilename) =>
      _misses?.containsKey(songFilename) ?? false;

  Future<Map<String, double>> _loadMisses() {
    _missesLoad ??= DatabaseService.instance.getCoverMisses().then((value) {
      _misses = value;
      return value;
    }).catchError((_) {
      _misses = <String, double>{};
      return <String, double>{};
    });
    return _missesLoad!;
  }

  Future<void> _acquireSlot() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void _releaseSlot() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
      return;
    }
    _active--;
  }

  Future<String?> ensureCoverForSong(String songFilename) async {
    if (songFilename.isEmpty || _inFlight.contains(songFilename)) {
      return null;
    }

    final misses = await _loadMisses();

    final song = await DatabaseService.instance.getSongByFilename(songFilename);
    if (song == null) return null;

    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final existing = File(song.coverUrl!);
      if (await existing.exists() && await existing.length() > 0) {
        return song.coverUrl;
      }
    }

    final audioFile = File(song.url);
    final FileStat stat;
    try {
      stat = await audioFile.stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
    } catch (_) {
      return null;
    }
    final mtime = stat.modified.millisecondsSinceEpoch / 1000.0;

    // Already probed this exact version of the file and came up empty.
    final knownMiss = misses[songFilename];
    if (knownMiss != null && (knownMiss - mtime).abs() < 2.0) {
      return null;
    }

    _inFlight.add(songFilename);
    await _acquireSlot();
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final audioPath = song.url;
      final coversPath = coversDir.path;

      // The metadata read and byte scan can touch the whole file, so they run
      // off the UI thread. The FFmpeg fallback can't — it uses platform
      // channels — but it is now a genuine last resort.
      String? coverPath = await Isolate.run(
        () => ScannerService.extractCoverWithoutFFmpeg(
          audioPath,
          coversPath,
          songFilename,
        ),
      );

      coverPath ??= await ScannerService.extractCoverWithFFmpeg(
        audioFile,
        coversDir,
        songFilename,
      );

      if (coverPath == null) {
        misses[songFilename] = mtime;
        await DatabaseService.instance.markCoverMiss(songFilename, mtime);
        return null;
      }

      await DatabaseService.instance.insertSongsBatch([
        Song(
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
        ),
      ]);

      return coverPath;
    } catch (e) {
      debugPrint('CoverRefreshService: failed to refresh $songFilename: $e');
      return null;
    } finally {
      _releaseSlot();
      _inFlight.remove(songFilename);
    }
  }
}

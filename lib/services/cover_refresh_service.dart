import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../domain/services/embedded_cover_bytes.dart';
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

  /// Songs *this process* has probed and confirmed have no art.
  ///
  /// Deliberately separate from [_misses]. A row in the `cover_miss` table
  /// records what some device concluded at some point, and it travels with a
  /// restored database — so treating mere presence there as authoritative lets
  /// one phone's failures permanently suppress extraction on another. Only a
  /// miss established here, against this filesystem, blocks the tile gate.
  final Set<String> _confirmedMisses = {};

  /// Whether scheduling [ensureCoverForSong] for this song is known to be
  /// pointless *right now*, so recycled list tiles don't re-enqueue it on every
  /// rebuild. Not authoritative — [ensureCoverForSong] still re-checks mtime.
  bool isSuppressed(String songFilename) =>
      _confirmedMisses.contains(songFilename);

  /// Drops the whole negative cache, in memory and for the next load.
  ///
  /// For after a restore or a cover-cache wipe, when nothing previously
  /// recorded describes the files actually on this device any more.
  void invalidateMisses() {
    _misses = null;
    _missesLoad = null;
    _confirmedMisses.clear();
  }

  /// Forgets recorded misses for specific songs, so the next tile that wants
  /// one of them probes again.
  void forgetMisses(Iterable<String> filenames) {
    for (final filename in filenames) {
      _misses?.remove(filename);
      _confirmedMisses.remove(filename);
    }
  }

  /// Drops a rewritten cover from Flutter's decoded-image cache.
  ///
  /// [Image.file] keys on the path, so replacing the bytes at a path that was
  /// already displayed keeps showing the old bitmap until something evicts it.
  static Future<void> evictCoverFromImageCache(String path) async {
    try {
      await FileImage(File(path)).evict();
    } catch (_) {
      // No binding (tests) or nothing cached — neither is worth reporting.
    }
  }

  /// Whether extraction is running right now. Other passive background work
  /// uses this to stay out of the way of covers the user is actually looking
  /// at.
  bool get isBusy => _active > 0 || _inFlight.isNotEmpty;

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

  /// Whether [file] holds something an image decoder will actually accept.
  ///
  /// A plain exists/non-empty check is not enough: covers cached by older
  /// builds can be a full-size image with the tail of its picture frame's
  /// description glued to the front, which is a file of healthy length that
  /// nothing can decode. Those need re-extracting, so they must not pass.
  Future<bool> _isDecodableCover(File file) async {
    RandomAccessFile? handle;
    try {
      if (!await file.exists()) return false;
      if (await file.length() <= 0) return false;
      handle = await file.open();
      final head = await handle.read(imageSignatureProbeLength);
      return hasImageSignature(head);
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
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
      if (await _isDecodableCover(File(song.coverUrl!))) {
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

    // Already probed this exact version of the file and came up empty. Checking
    // the mtime here — rather than trusting the row's existence — is what makes
    // an inherited or stale miss cost one cheap re-probe instead of forever.
    final knownMiss = misses[songFilename];
    if (knownMiss != null && (knownMiss - mtime).abs() < 2.0) {
      _confirmedMisses.add(songFilename);
      return null;
    }

    _inFlight.add(songFilename);
    await _acquireSlot();
    try {
      final coversDir = await ScannerService.coversDirectory();

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
        _confirmedMisses.add(songFilename);
        await DatabaseService.instance.markCoverMiss(songFilename, mtime);
        return null;
      }

      // Extraction may have overwritten a path that is already on screen.
      await evictCoverFromImageCache(coverPath);

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

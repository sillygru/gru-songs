import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/services/embedded_cover_bytes.dart';
import '../domain/services/library_repair_policy.dart';
import '../models/song.dart';
import 'cache_service.dart';
import 'cover_refresh_service.dart';
import 'database_service.dart';
import 'scanner_service.dart';
import 'storage_service.dart';

/// What a repair run changed.
class LibraryRepairReport {
  final int rowsExamined;
  final int coversRepointed;
  final int coversCleared;
  final int urlsReresolved;
  final int rowsDropped;
  final int coverMissesCleared;

  /// Cover paths now backing a different row than before, so their decoded
  /// bitmaps must be evicted.
  final List<String> changedCoverPaths;

  /// Whether pruning was skipped because the music folders couldn't be read.
  final bool pruningSkipped;

  const LibraryRepairReport({
    this.rowsExamined = 0,
    this.coversRepointed = 0,
    this.coversCleared = 0,
    this.urlsReresolved = 0,
    this.rowsDropped = 0,
    this.coverMissesCleared = 0,
    this.changedCoverPaths = const [],
    this.pruningSkipped = false,
  });

  bool get madeChanges =>
      coversRepointed > 0 ||
      coversCleared > 0 ||
      urlsReresolved > 0 ||
      rowsDropped > 0;

  /// A one-line summary for a snackbar or an indexer result.
  String get summary {
    if (rowsExamined == 0) return 'No songs to repair';
    if (!madeChanges) return 'Library links are already correct';
    final parts = <String>[];
    if (coversRepointed > 0) parts.add('re-linked $coversRepointed covers');
    if (coversCleared > 0) parts.add('cleared $coversCleared dead covers');
    if (urlsReresolved > 0) parts.add('relocated $urlsReresolved tracks');
    if (rowsDropped > 0) parts.add('removed $rowsDropped missing tracks');
    return '${parts.first[0].toUpperCase()}${parts.first.substring(1)}'
        '${parts.length > 1 ? ', ${parts.skip(1).join(', ')}' : ''}';
  }
}

/// Reconciles the library table with the filesystem it is actually sitting on.
///
/// Restoring a backup replaces `wispie_data.db` wholesale, so the `song` table
/// arrives describing the device the archive came from: cover paths into a
/// directory that may hold nothing, audio paths that may not exist, and a
/// `cover_miss` table recording failures against files this device has never
/// seen. Nothing downstream notices — the scanner reuses rows it thinks are
/// current, and the lazy cover path gives up the moment a song's `url` doesn't
/// stat — so the covers simply stay missing.
///
/// What makes this cheap to undo is that a cover's cache filename is
/// `sha1(basename)` (see [ScannerService.coverKeyForFilename]), which is
/// identical on every device. A cover whose file survived can be found again by
/// recomputing the key; only genuinely absent art needs re-extracting.
class LibraryRepairService {
  static final LibraryRepairService instance = LibraryRepairService._();

  LibraryRepairService._();

  /// Re-links covers and audio paths, and prunes rows whose files are gone.
  ///
  /// [preImportSongs] are rows read before an import overwrote them; they win
  /// on anything describing this filesystem. [importedRows] are library rows an
  /// archive supplied but that were deliberately not written yet, so this pass
  /// is the only thing that ever writes the `song` table on an import path.
  Future<LibraryRepairReport> repairLibrary({
    List<Song>? preImportSongs,
    List<Song>? importedRows,
    bool dropUnresolvable = true,
    void Function(double progress, String label)? onProgress,
  }) async {
    onProgress?.call(0, 'Reading library…');

    final merged = await _mergedTargetRows(
      preImportSongs: preImportSongs,
      importedRows: importedRows,
    );
    if (merged.isEmpty) {
      return const LibraryRepairReport();
    }

    final coversDir = await ScannerService.coversDirectory();

    onProgress?.call(0.05, 'Locating music files…');
    final folders = await _readableMusicFolders();
    // Never prune against a filesystem we couldn't see. An unmounted card or a
    // permission we haven't been granted yet would otherwise read as a library
    // that no longer exists.
    final canPrune = dropUnresolvable && folders.isNotEmpty;

    final probes = await _probeRows(
      rows: merged,
      coversDirPath: coversDir.path,
      musicFolders: folders,
      onProgress: (fraction) =>
          onProgress?.call(0.1 + fraction * 0.8, 'Re-linking album art…'),
    );

    onProgress?.call(0.9, 'Saving…');

    final updates = <Song>[];
    final dropped = <String>[];
    final changedCovers = <String>[];
    var coversRepointed = 0;
    var coversCleared = 0;
    var urlsReresolved = 0;

    for (final row in merged) {
      final probe = probes[row.filename];
      if (probe == null) continue;

      final decision = decideRepair(
        current: row,
        probe: probe,
        dropUnresolvable: canPrune,
      );

      switch (decision.action) {
        case RepairAction.keep:
          break;
        case RepairAction.drop:
          dropped.add(row.filename);
        case RepairAction.update:
          updates.add(decision.row!);
          if (decision.coverRepointed) {
            coversRepointed++;
            final path = decision.row!.coverUrl;
            if (path != null) changedCovers.add(path);
          }
          if (decision.coverCleared) coversCleared++;
          if (decision.urlReresolved) urlsReresolved++;
      }
    }

    if (updates.isNotEmpty) {
      // The one caller allowed to null a cover: here a null is a considered
      // finding, not a failure to look.
      await DatabaseService.instance
          .insertSongsBatch(updates, preserveCoverUrl: false);
    }
    if (dropped.isNotEmpty) {
      await DatabaseService.instance.deleteSongsByFilenames(dropped);
    }

    final missesCleared =
        (await DatabaseService.instance.getCoverMisses()).length;
    await DatabaseService.instance.clearAllCoverMisses();
    CoverRefreshService.instance.invalidateMisses();

    // Deliberately not CacheService.pruneStaleSongCaches: it builds its keep-set
    // from the cover paths currently in the library and deletes everything else
    // under extracted_covers, which after a device change would delete the very
    // files this pass exists to find.

    // Let the next launch run a real scan rather than trusting restored rows.
    await CacheService.instance.markLibraryChanged();

    for (final path in changedCovers) {
      await CoverRefreshService.evictCoverFromImageCache(path);
    }

    onProgress?.call(1.0, 'Done');

    return LibraryRepairReport(
      rowsExamined: merged.length,
      coversRepointed: coversRepointed,
      coversCleared: coversCleared,
      urlsReresolved: urlsReresolved,
      rowsDropped: dropped.length,
      coverMissesCleared: missesCleared,
      changedCoverPaths: changedCovers,
      pruningSkipped: dropUnresolvable && !canPrune,
    );
  }

  /// The rows to repair: what's in the database, reconciled with anything an
  /// import staged and anything a wholesale database replacement overwrote.
  Future<List<Song>> _mergedTargetRows({
    List<Song>? preImportSongs,
    List<Song>? importedRows,
  }) async {
    final byFilename = <String, Song>{
      for (final song in await DatabaseService.instance.getAllSongs())
        song.filename: song,
    };

    for (final imported in importedRows ?? const <Song>[]) {
      final existing = byFilename[imported.filename];
      byFilename[imported.filename] = existing == null
          ? imported
          : mergeSongRows(local: existing, imported: imported);
    }

    for (final local in preImportSongs ?? const <Song>[]) {
      final current = byFilename[local.filename];
      byFilename[local.filename] = current == null
          ? local
          : mergeSongRows(local: local, imported: current);
    }

    return byFilename.values.toList();
  }

  Future<List<String>> _readableMusicFolders() async {
    try {
      // forceRefresh because the cached list is process-wide and may predate
      // the import that just rewrote it — and this pass decides what to delete.
      final folders =
          await StorageService().getMusicFolders(forceRefresh: true);
      final readable = <String>[];
      for (final folder in folders) {
        final path = folder['path'];
        if (path == null || path.isEmpty) continue;
        if (await Directory(path).exists()) readable.add(path);
      }
      return readable;
    } catch (e) {
      debugPrint('LibraryRepairService: could not read music folders: $e');
      return const [];
    }
  }

  /// Probes every row against the filesystem, off the UI thread.
  ///
  /// This is thousands of `stat` calls on a real library, so it runs in an
  /// isolate; only plain `dart:io` is used inside, no plugins.
  Future<Map<String, SongProbe>> _probeRows({
    required List<Song> rows,
    required String coversDirPath,
    required List<String> musicFolders,
    void Function(double fraction)? onProgress,
  }) async {
    final payload = [
      for (final row in rows)
        _ProbeRequest(
          filename: row.filename,
          url: row.url,
          coverUrl: row.coverUrl,
        ),
    ];

    final receivePort = ReceivePort();
    final completer = Completer<Map<String, SongProbe>>();
    receivePort.listen((message) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is Map) {
        receivePort.close();
        completer.complete(Map<String, SongProbe>.from(message));
      } else {
        receivePort.close();
        completer.completeError(message ?? 'probe failed');
      }
    });

    await Isolate.spawn(
      _probeIsolate,
      _ProbeParams(
        requests: payload,
        coversDirPath: coversDirPath,
        musicFolders: musicFolders,
        sendPort: receivePort.sendPort,
      ),
    );

    return completer.future;
  }

  static Future<void> _probeIsolate(_ProbeParams params) async {
    try {
      // Only pay for the directory walk if something actually went missing.
      Map<String, String>? basenameIndex;

      final results = <String, SongProbe>{};
      for (var i = 0; i < params.requests.length; i++) {
        final request = params.requests[i];
        final audioExists = await File(request.url).exists();

        String? reresolved;
        double? mtime;
        if (audioExists) {
          try {
            mtime = (await File(request.url).stat())
                    .modified
                    .millisecondsSinceEpoch /
                1000.0;
          } catch (_) {
            // Existed a moment ago; treat the mtime as simply unknown.
          }
        } else {
          basenameIndex ??= await _buildBasenameIndex(params.musicFolders);
          reresolved = basenameIndex[request.filename];
          if (reresolved != null) {
            try {
              mtime = (await File(reresolved).stat())
                      .modified
                      .millisecondsSinceEpoch /
                  1000.0;
            } catch (_) {}
          }
        }

        results[request.filename] = SongProbe(
          audioExists: audioExists,
          reresolvedUrl: reresolved,
          validCoverPath: await _resolveCover(
            storedPath: request.coverUrl,
            coversDirPath: params.coversDirPath,
            filename: request.filename,
          ),
          mtime: mtime,
        );

        if (i % 200 == 0) {
          params.sendPort.send((i + 1) / params.requests.length);
        }
      }

      params.sendPort.send(results);
    } catch (e) {
      params.sendPort.send('$e');
    }
  }

  /// The cover backing [filename], preferring the stored path and falling back
  /// to the hash-derived name in the current covers directory.
  static Future<String?> _resolveCover({
    required String? storedPath,
    required String coversDirPath,
    required String filename,
  }) async {
    if (storedPath != null &&
        storedPath.isNotEmpty &&
        await _isUsableCover(File(storedPath))) {
      return storedPath;
    }

    for (final candidate
        in ScannerService.coverCandidatePaths(coversDirPath, filename)) {
      if (candidate == storedPath) continue;
      if (await _isUsableCover(File(candidate))) return candidate;
    }
    return null;
  }

  static Future<bool> _isUsableCover(File file) async {
    RandomAccessFile? handle;
    try {
      if (!await file.exists()) return false;
      if (await file.length() <= 0) return false;
      handle = await file.open();
      return hasImageSignature(await handle.read(imageSignatureProbeLength));
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  /// basename -> absolute path for everything playable under [folders].
  ///
  /// Last one wins on a collision, matching the `song` table's own basename
  /// primary key.
  static Future<Map<String, String>> _buildBasenameIndex(
      List<String> folders) async {
    final index = <String, String>{};
    for (final folder in folders) {
      try {
        final dir = Directory(folder);
        if (!await dir.exists()) continue;
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          if (!ScannerService.isSupportedMediaPath(entity.path)) continue;
          index[p.basename(entity.path)] = entity.path;
        }
      } catch (_) {
        // A folder we can't walk contributes nothing; the caller already
        // refuses to prune when folders are unreadable.
      }
    }
    return index;
  }
}

class _ProbeRequest {
  final String filename;
  final String url;
  final String? coverUrl;

  const _ProbeRequest({
    required this.filename,
    required this.url,
    this.coverUrl,
  });
}

class _ProbeParams {
  final List<_ProbeRequest> requests;
  final String coversDirPath;
  final List<String> musicFolders;
  final SendPort sendPort;

  const _ProbeParams({
    required this.requests,
    required this.coversDirPath,
    required this.musicFolders,
    required this.sendPort,
  });
}

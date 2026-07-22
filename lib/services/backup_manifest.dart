import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The kinds of content a backup archive can carry.
enum BackupContentType {
  userStats,
  userData,
  userSettings,
  coverCache,
  libraryCache,
  searchIndex,
  waveformCache,
  colorCache,
  lyricsCache,
}

/// One piece of cached content: where it lives on disk and where it is stored
/// inside a backup archive.
///
/// This is the single source of truth shared by the backup writer and the
/// restore path, so a bucket can never be captured from one place and written
/// back to another.
class BackupArtifact {
  final BackupContentType type;

  /// Path inside the archive, relative to the archive root.
  final String archivePath;

  /// Absolute path of the live location this artifact is read from and
  /// restored to.
  final String sourcePath;

  /// Whether [sourcePath] is a directory (copied recursively) or a single file.
  final bool isDirectory;

  /// Optional filter applied when a directory holds more than this bucket.
  final bool Function(File file)? filter;

  const BackupArtifact({
    required this.type,
    required this.archivePath,
    required this.sourcePath,
    required this.isDirectory,
    this.filter,
  });
}

/// Directory names used inside `gru_cache_v3`, mirrored from [CacheService].
const String _blurredCacheDir = 'blurred_cache';
const String _notificationCoverCacheDir = 'notification_cover_cache';
const String _lyricsCacheDir = 'lyrics_cache';

/// Builds the manifest of cache artifacts for the current device paths.
///
/// Documents/support directories are resolved once per call; the returned list
/// is safe to filter by [BackupContentType].
Future<List<BackupArtifact>> cacheArtifacts() async {
  final docDir = await getApplicationDocumentsDirectory();
  final supportDir = await getApplicationSupportDirectory();
  final v3Dir = p.join(supportDir.path, 'gru_cache_v3');

  return [
    // Covers: the real artwork lives in extracted_covers; the v3 directories
    // hold derived thumbnails.
    BackupArtifact(
      type: BackupContentType.coverCache,
      archivePath: 'cache/covers/extracted',
      sourcePath: p.join(supportDir.path, 'extracted_covers'),
      isDirectory: true,
    ),
    BackupArtifact(
      type: BackupContentType.coverCache,
      archivePath: 'cache/covers/blurred',
      sourcePath: p.join(v3Dir, _blurredCacheDir),
      isDirectory: true,
    ),
    BackupArtifact(
      type: BackupContentType.coverCache,
      archivePath: 'cache/covers/notification',
      sourcePath: p.join(v3Dir, _notificationCoverCacheDir),
      isDirectory: true,
    ),
    BackupArtifact(
      type: BackupContentType.libraryCache,
      archivePath: 'cache/library/cached_songs.json',
      sourcePath: p.join(docDir.path, 'cached_songs.json'),
      isDirectory: false,
    ),
    BackupArtifact(
      type: BackupContentType.searchIndex,
      archivePath: 'cache/search/wispie_search_index.db',
      sourcePath: p.join(docDir.path, 'wispie_search_index.db'),
      isDirectory: false,
    ),
    BackupArtifact(
      type: BackupContentType.waveformCache,
      archivePath: 'cache/waveforms',
      sourcePath: v3Dir,
      isDirectory: true,
      filter: _isWaveformFile,
    ),
    BackupArtifact(
      type: BackupContentType.colorCache,
      archivePath: 'cache/color/palette_cache.json',
      sourcePath: p.join(supportDir.path, 'palette_cache.json'),
      isDirectory: false,
    ),
    BackupArtifact(
      type: BackupContentType.colorCache,
      archivePath: 'cache/color/palettes',
      sourcePath: p.join(supportDir.path, 'palettes'),
      isDirectory: true,
    ),
    BackupArtifact(
      type: BackupContentType.lyricsCache,
      archivePath: 'cache/lyrics',
      sourcePath: p.join(v3Dir, _lyricsCacheDir),
      isDirectory: true,
    ),
  ];
}

bool _isWaveformFile(File file) =>
    p.basename(file.path).startsWith('waveform_');

/// Copies an artifact's live content into [stagingRoot] under its archive path.
///
/// Returns the number of files staged (0 when the source does not exist).
Future<int> stageArtifact(BackupArtifact artifact, String stagingRoot) async {
  final target = p.join(stagingRoot, artifact.archivePath);

  if (!artifact.isDirectory) {
    final source = File(artifact.sourcePath);
    if (!await source.exists()) return 0;
    await Directory(p.dirname(target)).create(recursive: true);
    await source.copy(target);
    return 1;
  }

  final sourceDir = Directory(artifact.sourcePath);
  if (!await sourceDir.exists()) return 0;

  var staged = 0;
  await for (final entity
      in sourceDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (artifact.filter != null && !artifact.filter!(entity)) continue;

    final relative = p.relative(entity.path, from: sourceDir.path);
    final destination = File(p.join(target, relative));
    await destination.parent.create(recursive: true);
    await entity.copy(destination.path);
    staged++;
  }
  return staged;
}

/// Copies an artifact back from an extracted archive at [archiveRoot] to its
/// live location. Existing files are overwritten; unrelated files are kept.
///
/// Returns the number of files restored (0 when the archive lacks this bucket).
Future<int> restoreArtifact(BackupArtifact artifact, String archiveRoot) async {
  final source = p.join(archiveRoot, artifact.archivePath);

  if (!artifact.isDirectory) {
    final file = File(source);
    if (!await file.exists()) return 0;
    await Directory(p.dirname(artifact.sourcePath)).create(recursive: true);
    await file.copy(artifact.sourcePath);
    return 1;
  }

  final sourceDir = Directory(source);
  if (!await sourceDir.exists()) return 0;

  var restored = 0;
  await for (final entity
      in sourceDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final relative = p.relative(entity.path, from: sourceDir.path);
    final destination = File(p.join(artifact.sourcePath, relative));
    await destination.parent.create(recursive: true);
    await entity.copy(destination.path);
    restored++;
  }
  return restored;
}

/// Whether an extracted archive at [archiveRoot] carries any content for [type].
Future<bool> archiveHasContent(
  List<BackupArtifact> artifacts,
  BackupContentType type,
  String archiveRoot,
) async {
  for (final artifact in artifacts.where((a) => a.type == type)) {
    final path = p.join(archiveRoot, artifact.archivePath);
    if (artifact.isDirectory) {
      final dir = Directory(path);
      if (await dir.exists() &&
          await dir.list(recursive: true).any((e) => e is File)) {
        return true;
      }
    } else if (await File(path).exists()) {
      return true;
    }
  }
  return false;
}

/// Extracts an archive entry name into [root], rejecting entries that would
/// escape it (zip-slip).
File? safeArchiveTarget(String root, String entryName) {
  final normalized = p.normalize(entryName);
  if (p.isAbsolute(normalized) ||
      normalized.split(RegExp(r'[/\\]')).contains('..')) {
    debugPrint('Skipping unsafe archive entry: $entryName');
    return null;
  }
  final target = File(p.join(root, normalized));
  if (!p.isWithin(root, target.path)) {
    debugPrint('Skipping unsafe archive entry: $entryName');
    return null;
  }
  return target;
}

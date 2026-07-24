import 'package:path/path.dart' as p;

import '../../models/song.dart';

/// Decides what to do with library rows whose stored paths no longer describe
/// the device the app is running on.
///
/// This is the pure half of the repair pass: the caller does the filesystem
/// probing and hands the results in, so every merge and drop decision here can
/// be exercised directly in tests. Keep it free of I/O.

/// What a probe found on disk for one row.
class SongProbe {
  /// Whether the row's stored [Song.url] still resolves to a file.
  final bool audioExists;

  /// Where the audio actually lives, when [audioExists] is false but a file of
  /// the same name turned up under a configured music folder.
  final String? reresolvedUrl;

  /// A cover file that exists and looks decodable — either the row's stored
  /// path, or one recomputed from the filename hash.
  final String? validCoverPath;

  /// The audio file's modification time, when it could be read.
  final double? mtime;

  const SongProbe({
    required this.audioExists,
    this.reresolvedUrl,
    this.validCoverPath,
    this.mtime,
  });

  /// Whether this row corresponds to a file we can point at, one way or another.
  bool get resolvable => audioExists || reresolvedUrl != null;
}

enum RepairAction {
  /// Nothing about the row needs changing.
  keep,

  /// The row needs writing back with [RepairDecision.row].
  update,

  /// The file is gone and couldn't be found anywhere; delete the row.
  drop,
}

class RepairDecision {
  final RepairAction action;

  /// The row to persist. Non-null exactly when [action] is
  /// [RepairAction.update].
  final Song? row;

  /// Whether this decision re-pointed a cover at a file that exists.
  final bool coverRepointed;

  /// Whether this decision cleared a cover path that no longer resolves.
  final bool coverCleared;

  /// Whether this decision moved the row to a rediscovered audio path.
  final bool urlReresolved;

  const RepairDecision({
    required this.action,
    this.row,
    this.coverRepointed = false,
    this.coverCleared = false,
    this.urlReresolved = false,
  });

  static const RepairDecision keep = RepairDecision(action: RepairAction.keep);
  static const RepairDecision drop = RepairDecision(action: RepairAction.drop);
}

/// The placeholder shape a fast scan writes before enrichment runs.
///
/// Rows in this state carry no information, so anything else wins over them.
bool isPlaceholderMetadata(Song song) {
  return song.artist == 'Unknown Artist' &&
      song.album == 'Unknown Album' &&
      song.title == p.basenameWithoutExtension(song.filename);
}

/// Combines a row scanned on this device with the same row from an import.
///
/// The split is by what each side is actually authoritative about: [local]
/// describes this filesystem — where the file is, when it was last touched,
/// which cover was extracted here — while [imported] carries the user's
/// history and any metadata they edited. Getting this backwards is what makes
/// a restore look like it erased the library.
Song mergeSongRows({required Song local, required Song imported}) {
  final localIsPlaceholder = isPlaceholderMetadata(local);
  final importedIsPlaceholder = isPlaceholderMetadata(imported);

  // Prefer whichever side actually has metadata; on a tie the import wins,
  // since it may hold edits the user made deliberately.
  final metadataSource =
      (importedIsPlaceholder && !localIsPlaceholder) ? local : imported;

  return Song(
    title: metadataSource.title,
    artist: metadataSource.artist,
    album: metadataSource.album,
    filename: local.filename,
    // Paths and mtime are properties of this device, never of the archive.
    url: local.url,
    coverUrl: local.coverUrl ?? imported.coverUrl,
    mtime: local.mtime ?? imported.mtime,
    hasLyrics: local.hasLyrics || imported.hasLyrics,
    // Never lose plays, and keep the earliest "date added" we have evidence of.
    playCount: local.playCount > imported.playCount
        ? local.playCount
        : imported.playCount,
    createdEpochSec:
        _minNullable(local.createdEpochSec, imported.createdEpochSec),
    duration: local.duration ?? imported.duration,
    songDateEpochSec: local.songDateEpochSec ?? imported.songDateEpochSec,
  );
}

double? _minNullable(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}

/// Works out what [current] needs, given what the filesystem said about it.
///
/// [dropUnresolvable] must be false whenever the probe couldn't see the music
/// folders at all — an unmounted card would otherwise read as a library that
/// no longer exists.
RepairDecision decideRepair({
  required Song current,
  required SongProbe probe,
  required bool dropUnresolvable,
}) {
  if (!probe.resolvable) {
    return dropUnresolvable ? RepairDecision.drop : RepairDecision.keep;
  }

  final newUrl = probe.audioExists ? current.url : probe.reresolvedUrl!;
  final urlChanged = newUrl != current.url;

  final currentCover = current.coverUrl;
  final hasCurrentCover = currentCover != null && currentCover.isNotEmpty;
  final newCover = probe.validCoverPath;

  final coverRepointed = newCover != null && newCover != currentCover;
  final coverCleared = newCover == null && hasCurrentCover;
  final mtimeChanged = probe.mtime != null && probe.mtime != current.mtime;

  if (!urlChanged && !coverRepointed && !coverCleared && !mtimeChanged) {
    return RepairDecision.keep;
  }

  return RepairDecision(
    action: RepairAction.update,
    row: current.copyWith(
      url: urlChanged ? newUrl : null,
      coverUrl: newCover,
      // A dead cover path has to become null, not stay dangling: null is what
      // lets lazy extraction pick the song up again.
      clearCoverUrl: coverCleared,
      mtime: probe.mtime,
    ),
    coverRepointed: coverRepointed,
    coverCleared: coverCleared,
    urlReresolved: urlChanged,
  );
}

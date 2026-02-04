import '../models/song.dart';

enum ArtistBulkMode { set, append, replace }

enum TitleBulkMode { replace }

class BulkMetadataPlan {
  final ArtistBulkMode? artistMode;
  final String artistValue;
  final String artistFind;
  final String artistReplace;
  final String artistJoiner;

  final TitleBulkMode? titleMode;
  final String titleFind;
  final String titleReplace;
  final bool titleCaseSensitive;

  final String? albumValue;

  BulkMetadataPlan({
    this.artistMode,
    this.artistValue = '',
    this.artistFind = '',
    this.artistReplace = '',
    this.artistJoiner = ' / ',
    this.titleMode,
    this.titleFind = '',
    this.titleReplace = '',
    this.titleCaseSensitive = false,
    this.albumValue,
  });

  bool get isEmpty =>
      artistMode == null && titleMode == null && albumValue == null;

  Song apply(Song song) {
    String newArtist = song.artist;
    String newTitle = song.title;
    String newAlbum = song.album;

    // Apply Artist changes
    if (artistMode != null) {
      switch (artistMode!) {
        case ArtistBulkMode.set:
          if (artistValue.isNotEmpty) newArtist = artistValue;
          break;
        case ArtistBulkMode.append:
          if (artistValue.isNotEmpty) {
            newArtist = song.artist.isEmpty
                ? artistValue
                : '${song.artist}$artistJoiner$artistValue';
          }
          break;
        case ArtistBulkMode.replace:
          if (artistFind.isNotEmpty) {
            newArtist = song.artist.replaceAll(artistFind, artistReplace);
          }
          break;
      }
    }

    // Apply Title changes
    if (titleMode == TitleBulkMode.replace && titleFind.isNotEmpty) {
      if (titleCaseSensitive) {
        newTitle = song.title.replaceAll(titleFind, titleReplace);
      } else {
        // Simple case-insensitive replacement logic
        final escapedFind = RegExp.escape(titleFind);
        newTitle = song.title.replaceAll(
            RegExp(escapedFind, caseSensitive: false), titleReplace);
      }
    }

    // Apply Album changes
    if (albumValue != null && albumValue!.isNotEmpty) {
      newAlbum = albumValue!;
    }

    return Song(
      title: newTitle,
      artist: newArtist,
      album: newAlbum,
      filename: song.filename,
      url: song.url,
      lyricsUrl: song.lyricsUrl,
      coverUrl: song.coverUrl,
      playCount: song.playCount,
      duration: song.duration,
      mtime: song.mtime,
    );
  }

  int countChanges(List<Song> songs) {
    if (isEmpty) return 0;
    int count = 0;
    for (final song in songs) {
      final updated = apply(song);
      if (updated.title != song.title ||
          updated.artist != song.artist ||
          updated.album != song.album) {
        count++;
      }
    }
    return count;
  }

  List<BulkMetadataPreview> buildPreview(List<Song> songs, {int limit = 3}) {
    if (isEmpty) return [];
    final changed = <BulkMetadataPreview>[];
    for (final song in songs) {
      final updated = apply(song);
      if (updated.title != song.title ||
          updated.artist != song.artist ||
          updated.album != song.album) {
        changed.add(BulkMetadataPreview(original: song, updated: updated));
        if (changed.length >= limit) break;
      }
    }
    return changed;
  }
}

class BulkMetadataPreview {
  final Song original;
  final Song updated;

  BulkMetadataPreview({required this.original, required this.updated});
}

class BulkMetadataResult {
  final int updated;
  final List<String> failedFilenames;

  BulkMetadataResult({required this.updated, required this.failedFilenames});
}

class BulkMetadataService {
  static List<BulkMetadataPreview> previewChanges(
      List<Song> songs, BulkMetadataPlan plan) {
    if (plan.isEmpty) return [];
    return songs
        .map((s) => BulkMetadataPreview(original: s, updated: plan.apply(s)))
        .toList();
  }
}

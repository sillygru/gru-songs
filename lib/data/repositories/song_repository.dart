import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/song.dart';
import '../../services/ffmpeg_service.dart';

class SongRepository {
  final FFmpegService _ffmpegService = FFmpegService();
  static const String _lyricsCacheFolder = 'lyrics_cache';

  SongRepository();

  Future<List<Song>> getSongs() async {
    // Local-only - songs are managed by the scanner service
    return [];
  }

  /// Gets lyrics from embedded metadata in the audio file using FFmpeg.
  /// Always tries to read lyrics regardless of hasLyrics flag.
  Future<String?> getLyrics(Song song) async {
    if (kDebugMode) {
      debugPrint('SongRepository: Getting lyrics for ${song.filename}');
      debugPrint('SongRepository: File path: ${song.url}');
      debugPrint('SongRepository: hasLyrics flag: ${song.hasLyrics}');
    }

    final cacheEntry = await _readLyricsCache(song);
    if (cacheEntry != null &&
        cacheEntry.isFresh &&
        cacheEntry.hasLyrics &&
        cacheEntry.lyrics != null) {
      return cacheEntry.lyrics;
    }

    final lyrics = await _ffmpegService.getLyrics(song.url);
    final normalizedLyrics =
        (lyrics != null && lyrics.trim().isNotEmpty) ? lyrics : null;
    await _writeLyricsCache(song, normalizedLyrics);

    if (kDebugMode) {
      if (normalizedLyrics != null) {
        debugPrint(
            'SongRepository: Found lyrics (${normalizedLyrics.length} chars)');
      } else {
        debugPrint('SongRepository: No lyrics found');
      }
    }

    return normalizedLyrics;
  }

  /// Checks if a song has lyrics using cached data first, then FFmpeg if needed.
  Future<bool> hasLyrics(Song song) async {
    final cacheEntry = await _readLyricsCache(song);
    if (cacheEntry != null && cacheEntry.isFresh) {
      return cacheEntry.hasLyrics;
    }

    if (song.hasLyrics) {
      await _writeLyricsCache(song, null, hasLyricsOverride: true);
      return true;
    }

    final lyrics = await getLyrics(song);
    return lyrics != null && lyrics.isNotEmpty;
  }

  /// Checks if a lyrics cache entry exists for this song (regardless of whether it has lyrics or not).
  /// This is useful for rebuild operations to know if a song has already been checked.
  Future<bool> hasLyricsCacheEntry(Song song) async {
    final cacheEntry = await _readLyricsCache(song);
    return cacheEntry != null && cacheEntry.isFresh;
  }

  Future<void> clearLyricsCache() async {
    final dir = await _getLyricsCacheDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> invalidateLyricsCache(Song song) async {
    final cacheFile = await _getCacheFileForSong(song);
    if (await cacheFile.exists()) {
      await cacheFile.delete();
    }
  }

  Future<_LyricsCacheEntry?> _readLyricsCache(Song song) async {
    try {
      final cacheFile = await _getCacheFileForSong(song);
      if (!await cacheFile.exists()) return null;

      final raw = await cacheFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final file = File(song.url);
      if (!await file.exists()) return null;
      final mtime = await file.lastModified();

      return _LyricsCacheEntry.fromJson(
        decoded,
        expectedMtimeMs: mtime.millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLyricsCache(
    Song song,
    String? lyrics, {
    bool? hasLyricsOverride,
  }) async {
    try {
      final file = File(song.url);
      if (!await file.exists()) return;
      final mtime = await file.lastModified();
      final hasLyrics =
          hasLyricsOverride ?? (lyrics != null && lyrics.isNotEmpty);

      final cacheFile = await _getCacheFileForSong(song);
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(jsonEncode({
        'mtimeMs': mtime.millisecondsSinceEpoch,
        'hasLyrics': hasLyrics,
        if (lyrics != null && lyrics.isNotEmpty) 'lyrics': lyrics,
      }));
    } catch (_) {
      // Cache failures should never block playback/UI.
    }
  }

  Future<File> _getCacheFileForSong(Song song) async {
    final dir = await _getLyricsCacheDirectory();
    final digest = sha1.convert(utf8.encode(song.url)).toString();
    return File(p.join(dir.path, '$digest.json'));
  }

  Future<Directory> _getLyricsCacheDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(
        p.join(supportDir.path, 'gru_cache_v3', _lyricsCacheFolder));
  }
}

class _LyricsCacheEntry {
  final bool isFresh;
  final bool hasLyrics;
  final String? lyrics;

  _LyricsCacheEntry({
    required this.isFresh,
    required this.hasLyrics,
    required this.lyrics,
  });

  factory _LyricsCacheEntry.fromJson(
    Map<String, dynamic> json, {
    required int expectedMtimeMs,
  }) {
    final cachedMtime = (json['mtimeMs'] as num?)?.toInt();
    return _LyricsCacheEntry(
      isFresh: cachedMtime != null && cachedMtime == expectedMtimeMs,
      hasLyrics: json['hasLyrics'] == true,
      lyrics: json['lyrics'] as String?,
    );
  }
}

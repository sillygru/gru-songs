import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'database_service.dart';
import 'scanner_service.dart';

class CoverRefreshService {
  static final CoverRefreshService instance = CoverRefreshService._internal();

  CoverRefreshService._internal();

  final Set<String> _inFlight = {};

  Future<String?> ensureCoverForSong(String songFilename) async {
    if (songFilename.isEmpty || _inFlight.contains(songFilename)) {
      return null;
    }

    final song = await DatabaseService.instance.getSongByFilename(songFilename);
    if (song == null) return null;

    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final existing = File(song.coverUrl!);
      if (await existing.exists() && await existing.length() > 0) {
        return song.coverUrl;
      }
    }

    final audioFile = File(song.url);
    if (!await audioFile.exists()) return null;

    _inFlight.add(songFilename);
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final stat = await audioFile.stat();
      final mtimeMs = song.mtime != null
          ? (song.mtime! * 1000).round()
          : stat.modified.millisecondsSinceEpoch;
      final hash = md5.convert(utf8.encode(audioFile.path)).toString();

      final coverPath = await ScannerService.extractCoverForFile(
        audioFile,
        coversDir,
        hash,
        mtimeMs,
        useFFmpegFallback: true,
      );
      if (coverPath == null) return null;

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
      _inFlight.remove(songFilename);
    }
  }
}

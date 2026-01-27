import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../models/song.dart';
import '../../services/storage_service.dart';
import '../../services/android_storage_service.dart';
import 'package:path/path.dart' as p;

class SongRepository {
  SongRepository();

  Future<List<Song>> getSongs() async {
    // Local-only - songs are managed by the scanner service
    return [];
  }

  Future<String?> getLyrics(String url) async {
    try {
      // Handle different URI formats
      if (url.startsWith('file://')) {
        final filePath = Uri.decodeComponent(url.substring(7));
        final file = File(filePath);
        if (await file.exists()) {
          return await file.readAsString();
        }
      } else if (url.startsWith('/') || url.startsWith('C:\\')) {
        // Direct file paths
        final file = File(url);
        if (await file.exists()) {
          return await file.readAsString();
        }
      } else {
        // Try to handle as relative path with Android storage
        if (Platform.isAndroid) {
          final storage = StorageService();
          final lyricsTreeUri = await storage.getLyricsFolderTreeUri();
          final lyricsRoot = await storage.getLyricsFolderPath();

          if (lyricsTreeUri != null &&
              lyricsRoot != null &&
              p.isWithin(lyricsRoot, url)) {
            final relativePath = p.relative(url, from: lyricsRoot);
            return await AndroidStorageService.readFile(
              treeUri: lyricsTreeUri,
              relativePath: relativePath,
            );
          }
        }

        // Fallback: try as direct file path
        final file = File(url);
        if (await file.exists()) {
          return await file.readAsString();
        }
      }
    } catch (e) {
      debugPrint('Error reading lyrics file: $e');
    }
    return null;
  }
}

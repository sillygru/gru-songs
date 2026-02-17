import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'color_extraction_service.dart';

class StorageAnalysisService {
  static final StorageAnalysisService instance = StorageAnalysisService._();
  StorageAnalysisService._();
  static const String _lyricsCacheDirName = 'lyrics_cache';

  Future<int> getDatabaseSize() async {
    int total = 0;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final files = [
        File(p.join(docDir.path, 'wispie_stats.db')),
        File(p.join(docDir.path, 'wispie_data.db')),
        // Include journal files if they exist
        File(p.join(docDir.path, 'wispie_stats.db-journal')),
        File(p.join(docDir.path, 'wispie_data.db-journal')),
        File(p.join(docDir.path, 'wispie_stats.db-wal')),
        File(p.join(docDir.path, 'wispie_data.db-wal')),
        File(p.join(docDir.path, 'wispie_stats.db-shm')),
        File(p.join(docDir.path, 'wispie_data.db-shm')),
      ];

      for (var f in files) {
        if (await f.exists()) {
          total += await f.length();
        }
      }
    } catch (e) {
      debugPrint('Error calculating database size: $e');
    }
    return total;
  }

  Future<int> getCoversCacheSize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (await coversDir.exists()) {
        return await _getDirSize(coversDir);
      }
    } catch (e) {
      debugPrint('Error calculating covers cache size: $e');
    }
    return 0;
  }

  Future<int> getBackupsSize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupsDir = Directory(p.join(appDir.path, 'backups'));
      if (await backupsDir.exists()) {
        return await _getDirSize(backupsDir);
      }
    } catch (e) {
      debugPrint('Error calculating backups size: $e');
    }
    return 0;
  }

  Future<int> getLibraryCacheSize() async {
    try {
      // The library cache includes:
      // 1. The cached_songs.json file in Documents directory
      // 2. The gru_cache_v3 directory in Application Support
      int total = 0;

      // Check for cached_songs.json files
      final docDir = await getApplicationDocumentsDirectory();
      await for (var entity in docDir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('cached_songs') && name.endsWith('.json')) {
            total += await entity.length();
          }
        }
      }

      // Check for gru_cache_v3 directory
      final supportDir = await getApplicationSupportDirectory();
      final v3Dir = Directory(p.join(supportDir.path, 'gru_cache_v3'));
      if (await v3Dir.exists()) {
        total += await _getDirSize(v3Dir);
      }

      return total;
    } catch (e) {
      debugPrint('Error calculating library cache size: $e');
    }
    return 0;
  }

  Future<int> getSearchIndexSize() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final searchIndexFile =
          File(p.join(docDir.path, 'wispie_search_index.db'));
      if (await searchIndexFile.exists()) {
        return await searchIndexFile.length();
      }
    } catch (e) {
      debugPrint('Error calculating search index size: $e');
    }
    return 0;
  }

  Future<int> getWaveformCacheSize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(supportDir.path, 'gru_cache_v3'));
      if (await cacheDir.exists()) {
        int total = 0;
        await for (var entity
            in cacheDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('waveform_') && name.endsWith('.json')) {
              total += await entity.length();
            }
          }
        }
        return total;
      }
    } catch (e) {
      debugPrint('Error calculating waveform cache size: $e');
    }
    return 0;
  }

  Future<int> getColorCacheSize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final colorCacheFile = File(p.join(supportDir.path, 'color_cache.json'));
      if (await colorCacheFile.exists()) {
        return await colorCacheFile.length();
      }
    } catch (e) {
      debugPrint('Error calculating color cache size: $e');
    }
    return 0;
  }

  Future<int> getLyricsCacheSize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final lyricsDir =
          Directory(p.join(supportDir.path, 'gru_cache_v3', _lyricsCacheDirName));
      if (await lyricsDir.exists()) {
        return await _getDirSize(lyricsDir);
      }
    } catch (e) {
      debugPrint('Error calculating lyrics cache size: $e');
    }
    return 0;
  }

  Future<int> _getDirSize(Directory dir) async {
    int total = 0;
    try {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (e) {
      debugPrint('Error calculating directory size for ${dir.path}: $e');
    }
    return total;
  }

  /// Clears only the database files
  Future<void> clearDatabase() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbFiles = [
        File(p.join(docDir.path, 'wispie_stats.db')),
        File(p.join(docDir.path, 'wispie_data.db')),
        File(p.join(docDir.path, 'wispie_stats.db-journal')),
        File(p.join(docDir.path, 'wispie_data.db-journal')),
        File(p.join(docDir.path, 'wispie_stats.db-wal')),
        File(p.join(docDir.path, 'wispie_data.db-wal')),
        File(p.join(docDir.path, 'wispie_stats.db-shm')),
        File(p.join(docDir.path, 'wispie_data.db-shm')),
      ];
      for (var f in dbFiles) {
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('Error clearing database: $e');
      rethrow;
    }
  }

  /// Clears only the covers cache
  Future<void> clearCoversCache() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing covers cache: $e');
      rethrow;
    }
  }

  /// Clears only the backups
  Future<void> clearBackups() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final backupsDir = Directory(p.join(docDir.path, 'backups'));
      if (await backupsDir.exists()) {
        await backupsDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing backups: $e');
      rethrow;
    }
  }

  /// Clears only the library cache (cached_songs.json and gru_cache_v3)
  Future<void> clearLibraryCache() async {
    try {
      // Clear cached_songs.json files
      final docDir = await getApplicationDocumentsDirectory();
      await for (var entity in docDir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('cached_songs') && name.endsWith('.json')) {
            await entity.delete();
          }
        }
      }

      // Clear gru_cache_v3 directory
      final supportDir = await getApplicationSupportDirectory();
      final v3Dir = Directory(p.join(supportDir.path, 'gru_cache_v3'));
      if (await v3Dir.exists()) {
        await v3Dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing library cache: $e');
      rethrow;
    }
  }

  /// Clears only the search index
  Future<void> clearSearchIndex() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final searchIndex = File(p.join(docDir.path, 'wispie_search_index.db'));
      if (await searchIndex.exists()) await searchIndex.delete();
    } catch (e) {
      debugPrint('Error clearing search index: $e');
      rethrow;
    }
  }

  /// Clears only the waveform cache
  Future<void> clearWaveformCache() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(supportDir.path, 'gru_cache_v3'));
      if (await cacheDir.exists()) {
        await for (var entity
            in cacheDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('waveform_') && name.endsWith('.json')) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing waveform cache: $e');
      rethrow;
    }
  }

  /// Clears only the color cache
  Future<void> clearColorCache() async {
    try {
      await ColorExtractionService.clearCache();
    } catch (e) {
      debugPrint('Error clearing color cache: $e');
      rethrow;
    }
  }

  /// Clears only the lyrics cache
  Future<void> clearLyricsCache() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final lyricsDir =
          Directory(p.join(supportDir.path, 'gru_cache_v3', _lyricsCacheDirName));
      if (await lyricsDir.exists()) {
        await lyricsDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing lyrics cache: $e');
      rethrow;
    }
  }

  Future<void> clearAllUserData() async {
    try {
      // 1. Delete Database Files
      await clearDatabase();

      // 2. Delete Song Covers
      await clearCoversCache();

      // 3. Delete Backups
      await clearBackups();

      // 4. Delete Library Cache (gru_cache_v3)
      await clearLibraryCache();

      // 5. Delete Search Index (if exists)
      await clearSearchIndex();

      // 6. Delete Waveform Cache
      await clearWaveformCache();

      // 7. Clear Shared Preferences
      await clearLyricsCache();

      // 8. Clear Shared Preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error clearing user data: $e');
      rethrow;
    }
  }
}

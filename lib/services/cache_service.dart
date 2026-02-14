import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// CacheService V3 - Offline First
/// Only handles app settings and sync data.
/// Automatically cleans up V1 and V2 caches.
class CacheService {
  static final CacheService instance = CacheService._internal();
  CacheService._internal();

  bool _initialized = false;
  late Directory _appSupportDir;

  // V3 specific: we keep a directory for sync-related cache (e.g. temporary sync files)
  late Directory _v3Dir;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _appSupportDir = await getApplicationSupportDirectory();
      _v3Dir = Directory(p.join(_appSupportDir.path, 'gru_cache_v3'));

      if (!await _v3Dir.exists()) {
        await _v3Dir.create(recursive: true);
      }

      await _cleanupOldCaches();
      _initialized = true;
    } catch (e) {
      debugPrint('CacheService init error: $e');
    }
  }

  Future<void> _cleanupOldCaches() async {
    try {
      // Cleanup V2
      final v2Dir = Directory(p.join(_appSupportDir.path, 'gru_cache_v2'));
      if (await v2Dir.exists()) {
        debugPrint('Cleaning up Gru Cache V2...');
        await v2Dir.delete(recursive: true);
      }

      // Cleanup V1 (Temp dirs)
      final tempDir = await getTemporaryDirectory();
      final legacyDirs = [
        'audio_cache',
        'image_cache',
        'libCacheManager',
        'libCachedImageData'
      ];
      for (var d in legacyDirs) {
        final dir = Directory(p.join(tempDir.path, d));
        if (await dir.exists()) {
          debugPrint('Cleaning up legacy cache: $d');
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error during cache cleanup: $e');
    }
  }

  Future<void> clearCache() async {
    await init();
    if (await _v3Dir.exists()) {
      final entries = _v3Dir.listSync();
      for (var e in entries) {
        await e.delete(recursive: true);
      }
    }
  }

  Future<int> getCacheSize() async {
    await init();

    // We use compute to run the heavy filesystem iteration in a background isolate
    // to prevent UI jank while calculating size for thousands of covers.
    return compute(_calculateCacheSizeInIsolate, {
      'v3Path': _v3Dir.path,
      'docPath': (await getApplicationDocumentsDirectory()).path,
      'supportPath': (await getApplicationSupportDirectory()).path,
    });
  }

  static Future<int> _calculateCacheSizeInIsolate(
      Map<String, String> paths) async {
    int total = 0;

    // 1. V3 Internal Directory Size
    final v3Dir = Directory(paths['v3Path']!);
    if (v3Dir.existsSync()) {
      try {
        for (var file in v3Dir.listSync(recursive: true)) {
          if (file is File) total += file.lengthSync();
        }
      } catch (_) {}
    }

    // 2. Extracted Covers Size (Application Support)
    final supportDir = Directory(paths['supportPath']!);
    final coversDir = Directory(p.join(supportDir.path, 'extracted_covers'));
    if (coversDir.existsSync()) {
      try {
        for (var file in coversDir.listSync(recursive: true)) {
          if (file is File) total += file.lengthSync();
        }
      } catch (_) {}
    }

    // 3. Mirrored Sync Data in Documents Directory
    final docDir = Directory(paths['docPath']!);
    if (docDir.existsSync()) {
      try {
        for (var entity in docDir.listSync()) {
          if (entity is File) {
            final name = p.basename(entity.path);
            // Count databases, stats, and cached sync metadata
            if (name.endsWith('.db') ||
                name.endsWith('.json') ||
                name.contains('_stats') ||
                name.contains('_data')) {
              total += entity.lengthSync();
            }
          }
        }
      } catch (_) {}
    }

    return total;
  }

  // Method to get a file in the V3 cache
  Future<File> getV3File(String filename) async {
    await init();
    return File(p.join(_v3Dir.path, filename));
  }
}

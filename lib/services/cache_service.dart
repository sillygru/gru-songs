import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'database_service.dart';

/// CacheService V3 - Offline First
/// Only handles app settings and sync data.
/// Automatically cleans up V1 and V2 caches.
class CacheService {
  static final CacheService instance = CacheService._internal();
  CacheService._internal();

  static const String _startupMaintenanceVersionKey =
      'startup_cache_maintenance_version';
  static const String _startupMaintenancePendingKey =
      'startup_cache_maintenance_pending';

  bool _initialized = false;
  bool _maintenanceRequested = false;
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
      _initialized = true;
    } catch (e) {
      debugPrint('CacheService init error: $e');
    }
  }

  Future<void> _cleanupLegacyCaches() async {
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

  Future<void> markLibraryChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_startupMaintenancePendingKey, true);
    } catch (e) {
      debugPrint('Error marking cache maintenance as pending: $e');
    }
  }

  Future<void> scheduleStartupMaintenance() async {
    if (_maintenanceRequested) return;
    _maintenanceRequested = true;

    unawaited(() async {
      try {
        await init();

        final prefs = await SharedPreferences.getInstance();
        final currentVersion = await _readAppVersion();
        final lastVersion = prefs.getString(_startupMaintenanceVersionKey);
        final pending = prefs.getBool(_startupMaintenancePendingKey) ?? false;

        if (!pending && lastVersion == currentVersion) {
          return;
        }

        final songs = await DatabaseService.instance.getAllSongs();
        await pruneStaleSongCaches(songs);
        await _cleanupLegacyCaches();

        await prefs.setString(_startupMaintenanceVersionKey, currentVersion);
        await prefs.setBool(_startupMaintenancePendingKey, false);
      } catch (e) {
        debugPrint('Startup cache maintenance failed: $e');
      } finally {
        _maintenanceRequested = false;
      }
    }());
  }

  Future<String> _readAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> pruneStaleSongCaches(List<Song> songs) async {
    await init();

    final supportDir = _appSupportDir.path;
    final songPayload = songs
        .map((song) => {
              'filename': song.filename,
              'coverUrl': song.coverUrl ?? '',
            })
        .toList(growable: false);

    await Isolate.run(() => _pruneCachesInIsolate({
          'supportDir': supportDir,
          'songs': songPayload,
        }));
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

  Future<File> getBlurredCacheFile(String songFilename) async {
    await init();
    final blurredDir = Directory(p.join(_v3Dir.path, 'blurred_cache'));
    if (!await blurredDir.exists()) {
      await blurredDir.create(recursive: true);
    }
    return File(p.join(blurredDir.path, 'blurred_$songFilename.jpg'));
  }

  Future<int> getBlurredCacheCount() async {
    await init();
    final blurredDir = Directory(p.join(_v3Dir.path, 'blurred_cache'));
    if (!await blurredDir.exists()) return 0;
    int count = 0;
    await for (final entity in blurredDir.list()) {
      if (entity is File && entity.path.endsWith('.jpg')) count++;
    }
    return count;
  }

  Future<File> getNotificationCoverCacheFile(String songFilename) async {
    await init();
    final notifDir = Directory(p.join(_v3Dir.path, 'notification_cover_cache'));
    if (!await notifDir.exists()) {
      await notifDir.create(recursive: true);
    }
    return File(p.join(notifDir.path, '$songFilename.jpg'));
  }
}

Future<void> _pruneCachesInIsolate(Map<String, dynamic> payload) async {
  final supportDir = Directory(payload['supportDir'] as String);
  final songs = List<Map<String, dynamic>>.from(payload['songs'] as List);

  final currentCoverPaths = <String>{};
  final currentBlurredPaths = <String>{};
  final currentNotificationPaths = <String>{};

  final blurredDir =
      Directory(p.join(supportDir.path, 'gru_cache_v3', 'blurred_cache'));
  final notificationDir = Directory(
      p.join(supportDir.path, 'gru_cache_v3', 'notification_cover_cache'));
  final extractedCoversDir =
      Directory(p.join(supportDir.path, 'extracted_covers'));

  for (final song in songs) {
    final coverUrl = (song['coverUrl'] as String?) ?? '';
    if (coverUrl.isNotEmpty) {
      currentCoverPaths.add(p.normalize(coverUrl));
    }

    final filename = (song['filename'] as String?) ?? '';
    if (filename.isNotEmpty) {
      currentBlurredPaths.add(
        p.normalize(p.join(blurredDir.path, 'blurred_$filename.jpg')),
      );
    }

    if (coverUrl.isNotEmpty) {
      final coverKey = p.basename(coverUrl).replaceAll(RegExp(r'[^\w\-]'), '_');
      currentNotificationPaths.add(
        p.normalize(p.join(notificationDir.path, '$coverKey.jpg')),
      );
    }
  }

  Future<int> pruneDirectory(Directory dir, Set<String> keepPaths) async {
    if (!await dir.exists()) return 0;
    int deleted = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final normalized = p.normalize(entity.path);
      if (!keepPaths.contains(normalized)) {
        try {
          await entity.delete();
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }

  Future<void> pruneEmptyDirectories(Directory dir) async {
    if (!await dir.exists()) return;
    final directories = <Directory>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is Directory &&
          p.normalize(entity.path) != p.normalize(dir.path)) {
        directories.add(entity);
      }
    }

    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      try {
        if (await directory.exists() && await directory.list().isEmpty) {
          await directory.delete();
        }
      } catch (_) {}
    }
  }

  await pruneDirectory(extractedCoversDir, currentCoverPaths);
  await pruneDirectory(blurredDir, currentBlurredPaths);
  await pruneDirectory(notificationDir, currentNotificationPaths);
  await pruneEmptyDirectories(extractedCoversDir);
  await pruneEmptyDirectories(blurredDir);
  await pruneEmptyDirectories(notificationDir);
}

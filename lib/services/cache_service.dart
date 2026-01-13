import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CacheEntry {
  final String filename;
  final String url;
  final String? version;
  final DateTime lastValidated;

  CacheEntry({
    required this.filename,
    required this.url,
    this.version,
    required this.lastValidated,
  });

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      filename: json['filename'],
      url: json['url'],
      version: json['version']?.toString(),
      lastValidated: DateTime.parse(json['lastValidated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'url': url,
      'version': version,
      'lastValidated': lastValidated.toIso8601String(),
    };
  }
}

class CacheService {
  static final CacheService instance = CacheService._internal();
  CacheService._internal();

  bool _initialized = false;
  late Directory _baseDir;
  late File _metadataFile;
  final Map<String, Map<String, CacheEntry>> _metadata = {
    'songs': {},
    'images': {},
    'lyrics': {},
  };

  final Map<String, Future<File?>> _activeDownloads = {};
  DateTime? _pausedUntil;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final docDir = await getApplicationSupportDirectory();
      _baseDir = Directory(p.join(docDir.path, 'gru_cache_v2'));
      
      bool isFirstV2Run = !await _baseDir.exists();
      if (isFirstV2Run) {
        await _baseDir.create(recursive: true);
        await _cleanupLegacyCache(); 
      }

      _metadataFile = File(p.join(_baseDir.path, 'metadata.json'));
      if (await _metadataFile.exists()) {
        try {
          final content = await _metadataFile.readAsString();
          final Map<String, dynamic> json = jsonDecode(content);
          json.forEach((category, entries) {
            if (_metadata.containsKey(category)) {
              _metadata[category] = (entries as Map<String, dynamic>).map(
                (key, value) => MapEntry(key, CacheEntry.fromJson(value)),
              );
            }
          });
        } catch (e) {
          debugPrint('Cache metadata corrupted, resetting: $e');
        }
      }
      _initialized = true;
    } catch (e) {
      debugPrint('CacheService init error: $e');
    }
  }

  bool get isPaused {
    if (_pausedUntil == null) return false;
    return DateTime.now().isBefore(_pausedUntil!);
  }

  void pauseOperations(Duration duration) {
    _pausedUntil = DateTime.now().add(duration);
    // Cancel any active downloads
    _activeDownloads.clear(); 
  }

  Future<File?> getFile(String category, String filename, String url, {String? version, bool blockOnMiss = true, bool triggerDownload = true}) async {
    await init();
    
    if (isPaused) {
      // If paused, only return from disk, never trigger download
      triggerDownload = false;
    }

    final categoryDir = Directory(p.join(_baseDir.path, category));
    if (!await categoryDir.exists()) await categoryDir.create(recursive: true);

    final filePath = p.join(categoryDir.path, filename);
    final file = File(filePath);
    final entry = _metadata[category]?[filename];

    if (await file.exists()) {
      if (entry == null) {
        _metadata[category]![filename] = CacheEntry(
          filename: filename,
          url: url,
          version: version,
          lastValidated: DateTime.now(),
        );
        _saveMetadata();
      } else if (version != null && entry.version != version && triggerDownload) {
        _downloadFile(category, filename, url, version);
      }
      return file;
    }

    if (!triggerDownload) return null;

    if (!blockOnMiss) {
      _downloadFile(category, filename, url, version);
      return null; 
    }
    
    return await _downloadFile(category, filename, url, version);
  }

  Future<File?> _downloadFile(String category, String filename, String url, String? version) async {
    if (isPaused) return null;
    
    final downloadKey = '$category:$filename';
    if (_activeDownloads.containsKey(downloadKey)) return _activeDownloads[downloadKey];

    final downloadFuture = _performDownload(category, filename, url, version);
    _activeDownloads[downloadKey] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _activeDownloads.remove(downloadKey);
    }
  }

  Future<File?> _performDownload(String category, String filename, String url, String? version) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (isPaused) return null; // Check again after long download

        final categoryDir = Directory(p.join(_baseDir.path, category));
        final filePath = p.join(categoryDir.path, filename);
        final tempFile = File('$filePath.tmp');
        await tempFile.writeAsBytes(response.bodyBytes);
        
        final file = File(filePath);
        String finalFilename = filename;
        
        try {
          if (await file.exists()) await file.delete();
          await tempFile.rename(filePath);
        } catch (e) {
          final altName = '${DateTime.now().millisecondsSinceEpoch}_$filename';
          final altPath = p.join(categoryDir.path, altName);
          await tempFile.rename(altPath);
          finalFilename = altName;
        }

        _metadata[category]![filename] = CacheEntry(
          filename: finalFilename,
          url: url,
          version: version ?? md5.convert(response.bodyBytes).toString(),
          lastValidated: DateTime.now(),
        );
        await _saveMetadata();
        return File(p.join(categoryDir.path, finalFilename));
      }
    } catch (e) {
      debugPrint('Error downloading $url: $e');
    }
    return null;
  }

  Future<void> _saveMetadata() async {
    try {
      final tmpFile = File('${_metadataFile.path}.tmp');
      await tmpFile.writeAsString(jsonEncode(_metadata));
      await tmpFile.rename(_metadataFile.path);
    } catch (e) {
      debugPrint('Error saving cache metadata: $e');
    }
  }

  Future<void> _cleanupLegacyCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dirs = ['audio_cache', 'image_cache', 'libCacheManager', 'libCachedImageData'];
      for (var d in dirs) {
        final dir = Directory(p.join(tempDir.path, d));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> clearCache({String? category}) async {
    await init();
    pauseOperations(const Duration(seconds: 10));

    if (category == null) {
      if (await _baseDir.exists()) await _baseDir.delete(recursive: true);
      _metadata.values.forEach((cat) => cat.clear());
      _initialized = false;
      await init();
    } else {
      final dir = Directory(p.join(_baseDir.path, category));
      if (await dir.exists()) await dir.delete(recursive: true);
      _metadata[category]?.clear();
      await _saveMetadata();
    }
  }

  Future<void> removeEntry(String category, String filename) async {
    await init();
    final entry = _metadata[category]?[filename];
    if (entry != null) {
      final file = File(p.join(_baseDir.path, category, entry.filename));
      if (await file.exists()) await file.delete();
      _metadata[category]!.remove(filename);
      await _saveMetadata();
    }
  }

  Future<Uri> getAudioUri(String filename, String url, {String? version, bool triggerDownload = true}) async {
    final file = await getFile('songs', filename, url, version: version, blockOnMiss: false, triggerDownload: triggerDownload);
    if (file != null) return Uri.file(file.path);
    return Uri.parse(url);
  }

  Future<int> getCacheSize({String? category}) async {
    await init();
    final targetDir = category == null ? _baseDir : Directory(p.join(_baseDir.path, category));
    if (!await targetDir.exists()) return 0;
    
    int total = 0;
    try {
      await for (var file in targetDir.list(recursive: true)) {
        if (file is File) total += await file.length();
      }
    } catch (_) {}
    return total;
  }

  Map<String, CacheEntry> getEntries(String category) {
    return _metadata[category] ?? {};
  }

  Future<String?> readString(String category, String filename, String url) async {
    final file = await getFile(category, filename, url);
    return file != null ? await file.readAsString() : null;
  }
}

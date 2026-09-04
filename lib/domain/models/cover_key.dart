import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../value_objects/filename.dart';

/// Typed identifier for cover and derived caches.
///
/// Replaces nullable `String? coverUrl` + ad-hoc `file://` normalization
/// scattered across waveform, FFmpeg and blur code with one value object.
/// The filename is the app's primary key for user data, so this key
/// is the sole place that knows how cache file names are derived.
class CoverKey {
  final String filename;

  const CoverKey(this.filename);

  bool get isEmpty => filename.isEmpty;
  bool get isNotEmpty => filename.isNotEmpty;

  /// Stable hash used for cache file names (mirrors CacheService._cacheKey).
  String get hash => sha1.convert(utf8.encode(filename)).toString();

  String waveformCacheName() => 'waveform_$hash.json';
  String beatMapCacheName() => 'beatmap_$hash.json';
  String blurredCacheName() => 'blurred_$hash.jpg';

  /// Normalized cache key for notification covers (basename of cover file).
  static String notificationKeyForCoverPath(String coverPath) {
    final base = coverPath.split('/').last.split('\\').last;
    final sanitized = base.replaceAll(RegExp(r'[^\w\-]'), '_');
    if (sanitized.isEmpty || sanitized == '_') return 'cover';
    return sanitized;
  }

  /// Normalize a possibly `file://` URI to a filesystem path.
  static String normalizePath(String path) {
    if (path.startsWith('file://')) {
      try {
        return Uri.parse(path).toFilePath();
      } catch (_) {
        return path;
      }
    }
    return path;
  }

  factory CoverKey.fromFilePath(String path) =>
      CoverKey(Filename.fromUrl(normalizePath(path)));

  @override
  bool operator ==(Object other) =>
      other is CoverKey && other.filename == filename;

  @override
  int get hashCode => filename.hashCode;

  @override
  String toString() => 'CoverKey($filename)';
}

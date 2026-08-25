import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'embedded_cover_bytes.dart';

/// Pure logic and I/O helpers for deduplicating, resizing, and caching cover art.
class CoverOptimizer {
  /// Maximum bounding dimension for cached cover images.
  /// 1024px gives retina clarity on phone/tablet/desktop screens while
  /// capping memory consumption to ~4MB decoded RGBA bitmap.
  static const int maxCoverDimension = 1024;

  /// Quality level for JPEG encoding (88 provides visually lossless quality).
  static const int jpegQuality = 88;

  /// Threshold under which already-compressed, correctly-sized images skip re-encoding.
  static const int fastPathByteLimit = 250 * 1024;

  /// Computes a content-addressable hash key for [bytes].
  static String computeContentKey(Uint8List bytes) {
    final hash = sha1.convert(bytes).toString();
    return 'c_$hash';
  }

  /// Checks whether a deduplicated cover already exists in [coversDirPath] for [contentKey].
  static String? findExistingCover(String coversDirPath, String contentKey) {
    for (final ext in const ['.jpg', '.webp', '.png', '.jpeg']) {
      final path = p.join(coversDirPath, '$contentKey$ext');
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) {
        return path;
      }
    }
    return null;
  }

  /// Optimizes and writes [rawBytes] to [coversDirPath] with content-addressable deduplication.
  ///
  /// If an identical cover image is already cached, returns the existing path immediately
  /// without disk writes or re-encoding.
  static Future<String> saveOptimizedCover(
    Uint8List rawBytes,
    String coversDirPath, {
    String? fallbackExtension,
    int maxDimension = maxCoverDimension,
    int quality = jpegQuality,
  }) async {
    final key = computeContentKey(rawBytes);
    final existing = findExistingCover(coversDirPath, key);
    if (existing != null) {
      return existing;
    }

    final ext = fallbackExtension ?? _sniffExtension(rawBytes) ?? '.jpg';

    // Decode to inspect dimensions and optimize.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(rawBytes);
    } catch (e) {
      debugPrint('CoverOptimizer: decode failed ($e), saving raw bytes');
    }

    if (decoded == null) {
      final targetPath = p.join(coversDirPath, '$key$ext');
      final file = File(targetPath);
      await file.writeAsBytes(rawBytes);
      return targetPath;
    }

    final bool isOversized =
        decoded.width > maxDimension || decoded.height > maxDimension;

    // Fast-path: If image is already correctly sized, reasonably small, and in JPEG/WebP format,
    // write directly without re-encoding CPU overhead.
    if (!isOversized &&
        rawBytes.length <= fastPathByteLimit &&
        (ext == '.jpg' || ext == '.webp')) {
      final targetPath = p.join(coversDirPath, '$key$ext');
      return await _writeAtomic(targetPath, rawBytes);
    }

    img.Image toEncode = decoded;
    if (isOversized) {
      final bool isWider = decoded.width >= decoded.height;
      final int targetW = isWider
          ? maxDimension
          : (decoded.width * maxDimension / decoded.height).round();
      final int targetH = isWider
          ? (decoded.height * maxDimension / decoded.width).round()
          : maxDimension;

      toEncode = img.copyResize(
        decoded,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.cubic,
      );
    }

    final Uint8List optimizedBytes =
        Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
    final targetPath = p.join(coversDirPath, '$key.jpg');
    return await _writeAtomic(targetPath, optimizedBytes);
  }

  static Future<String> _writeAtomic(String targetPath, Uint8List bytes) async {
    final parentDir = p.dirname(targetPath);
    final baseName = p.basenameWithoutExtension(targetPath);
    final tempPath = p.join(
        parentDir, '$baseName.tmp_${DateTime.now().microsecondsSinceEpoch}');
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);
    try {
      await tempFile.rename(targetPath);
      return targetPath;
    } catch (_) {
      if (await File(targetPath).exists()) return targetPath;
      return tempFile.path;
    }
  }

  static String? _sniffExtension(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (hasImageSignature(bytes)) {
      final embedded = recoverEmbeddedCover(bytes);
      return embedded?.extension;
    }
    return null;
  }
}

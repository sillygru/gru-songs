import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/cache_service.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/media_decode_gate.dart';
import '../models/cover_key.dart';

/// Decode and cache seam for media work.
///
/// Waveform decode is currently cache-only here; actual PCM decoding lives
/// in [WaveformService] until the adapter move lands. Cover/video extraction
/// is serialized through [MediaDecodeGate] so FFmpeg work does not overlap.
/// Cache invalidation is unified behind [CoverKey].
class MediaDecode {
  final CacheService _cache;
  final FFmpegService _ffmpeg;

  MediaDecode({CacheService? cache, FFmpegService? ffmpeg})
      : _cache = cache ?? CacheService.instance,
        _ffmpeg = ffmpeg ?? FFmpegService.instance;

  /// Returns cached waveform peaks for [key], if present.
  ///
  /// Cache-only helper; actual PCM decoding and progressive emission live
  /// in [WaveformService]. Does not hold [MediaDecodeGate].
  Future<List<double>> getCachedWaveform(CoverKey key) async {
    if (key.isEmpty) return const <double>[];
    final cacheFile = await _cache.getWaveformCacheFile(key.filename);
    if (!await cacheFile.exists()) return const <double>[];
    try {
      final content = await cacheFile.readAsString();
      if (content.isEmpty) return const <double>[];
      final decoded = await compute(_decodeJson, content);
      if (decoded.isEmpty) return const <double>[];
      return decoded.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      debugPrint(
          'MediaDecode: waveform cache read failed for ${key.filename}: $e');
      return const <double>[];
    }
  }

  /// Deprecated alias kept for any out-of-tree callers.
  @Deprecated('Use getCachedWaveform(CoverKey) instead')
  Future<List<double>> decodeWaveform({
    required CoverKey key,
    required String path,
    required Duration total,
    void Function(List<double>)? onPartial,
  }) =>
      getCachedWaveform(key);

  /// Extract an attached-picture cover from [inputPath] to [outputPath].
  ///
  /// Delegates to [FFmpegService.extractCover] but through the gate so
  /// it does not run beside a waveform decode of the same file.
  Future<String?> extractCover({
    required String inputPath,
    required String outputPath,
  }) {
    return MediaDecodeGate.run(
      () => _ffmpeg.extractCover(
        inputPath: inputPath,
        outputPath: outputPath,
      ),
      priority: MediaDecodePriority.normal,
    );
  }

  /// Extract a video thumbnail (decoded frame) from [inputPath].
  Future<String?> extractVideoThumbnail({
    required String inputPath,
    required String outputPath,
    int frameNumber = 5,
  }) {
    return MediaDecodeGate.run(
      () => _ffmpeg.extractVideoThumbnail(
        inputPath: inputPath,
        outputPath: outputPath,
        frameNumber: frameNumber,
      ),
      priority: MediaDecodePriority.normal,
    );
  }

  /// Blur helper seam — callers run `generateBlurredImageBytes` in
  /// `Isolate.run` directly so this module does not depend on `image`.
  /// Bypasses [MediaDecodeGate] because blurring is image work, not FFmpeg
  /// pipe work.
  Future<bool> generateBlurredImage({
    required String inputPath,
    required String outputPath,
    int width = 300,
    int height = 300,
    int blurSigma = 15,
  }) =>
      _ffmpeg.generateBlurredImage(
        inputPath: CoverKey.normalizePath(inputPath),
        outputPath: outputPath,
        width: width,
        height: height,
        blurSigma: blurSigma,
      );

  /// Cache invalidation unified behind CoverKey so callers do not pass
  /// raw strings with varying `file://` handling.
  Future<void> invalidateBlurredCache(CoverKey key) =>
      _cache.invalidateBlurredCache(key.filename);

  Future<void> invalidateWaveformCache(CoverKey key) async {
    try {
      final file = await _cache.getWaveformCacheFile(key.filename);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Typed helper for notification cover keys derived from cover paths.
  String notificationKey(String coverPath) =>
      CoverKey.notificationKeyForCoverPath(coverPath);
}

List<dynamic> _decodeJson(String content) {
  if (content.isEmpty) return <dynamic>[];
  try {
    final decoded = jsonDecode(content);
    if (decoded is List) return decoded;
  } catch (_) {}
  return <dynamic>[];
}

/// In-memory fake for tests — no FFmpeg, no files.
class FakeMediaDecode extends MediaDecode {
  final Map<String, List<double>> waveforms = {};

  FakeMediaDecode() : super(cache: CacheService.instance);

  @override
  Future<List<double>> getCachedWaveform(CoverKey key) async {
    return waveforms[key.filename] ?? List.filled(200, 0.5);
  }

  @override
  Future<String?> extractCover({
    required String inputPath,
    required String outputPath,
  }) async =>
      null;

  @override
  Future<String?> extractVideoThumbnail({
    required String inputPath,
    required String outputPath,
    int frameNumber = 5,
  }) async =>
      null;
}

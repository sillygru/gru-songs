import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_service.dart';
import 'ffmpeg_service.dart';
import 'media_decode_gate.dart';

class WaveformService {
  final CacheService _cacheService;

  WaveformService(this._cacheService);

  /// The fixed bar count every extracted waveform is bucketed into. Widgets use
  /// it to scale a partial emission (which carries fewer bars) to the width it
  /// should occupy, so the waveform reveals left-to-right as it decodes.
  static const int targetWaveformSamples = 2000;

  /// PCM bytes the decode writes per second: 4000 Hz, mono, 16-bit.
  static const int _pcmBytesPerSecond = 4000 * 2;

  /// One decode at a time. Parallel FFmpeg sessions fight the audio thread.
  Future<void> _chain = Future.value();

  final Map<String, Future<List<double>>> _inFlight = {};

  /// Progressive decodes keyed by filename, so re-subscribing mid-decode shares
  /// one decode instead of starting a second FFmpeg session for the same song.
  final Map<String, StreamController<List<double>>> _progressive = {};

  /// Completed waveforms keyed by filename, so an already-decoded song renders
  /// immediately on a later open without another disk read.
  final Map<String, List<double>> _memoryCache = {};

  /// Synchronous lookup of an already-decoded waveform, so the player bar can
  /// paint it on the very first frame without an async/disk round-trip.
  List<double>? cachedWaveformSync(String filename) => _memoryCache[filename];

  /// Fast check if the waveform for [filename] is already cached, either in
  /// memory (decoded this session) or on disk.
  Future<bool> isWaveformCached(String filename) async {
    if (filename.isEmpty) return false;
    if (_memoryCache.containsKey(filename)) return true;
    final cacheFile = await _cacheService.getWaveformCacheFile(filename);
    return cacheFile.exists();
  }

  Future<List<double>> getWaveform(String filename, String path) {
    if (path.isEmpty || path.startsWith('http')) {
      return Future.value(const []);
    }

    final existing = _inFlight[filename];
    if (existing != null) return existing;

    final work = _chain.then((_) => _getWaveform(filename, path));
    _chain = work.then((_) {}, onError: (_) {});
    _inFlight[filename] = work;
    work.whenComplete(() => _inFlight.remove(filename));
    return work;
  }

  Future<List<double>> _getWaveform(String filename, String path) async {
    final cached = _memoryCache[filename];
    if (cached != null) return cached;

    final cacheFile = await _cacheService.getWaveformCacheFile(filename);
    if (await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final List<dynamic> json = jsonDecode(content);
        final samples = json.cast<double>();
        _memoryCache[filename] = samples;
        return samples;
      } catch (e) {
        debugPrint('Error reading waveform cache: $e');
      }
    }

    final samples = await _extractWaveformFast(path);
    if (samples.isEmpty) return const [];

    _memoryCache[filename] = samples;
    try {
      final cachePath = cacheFile.path;
      await _isolateWriteWaveformCache(cachePath, samples);
    } catch (e) {
      debugPrint('Error writing waveform cache: $e');
    }

    return samples;
  }

  /// Emits the waveform for [filename] as it is being produced.
  ///
  /// A cached song yields its full list once. An uncached one starts the decode
  /// (through the shared gate, high priority) and, because FFmpeg writes the
  /// PCM output to a growing temp file, yields partial lists every few hundred
  /// milliseconds — each carrying only the bars decoded so far, so the player
  /// paints the waveform filling in left-to-right instead of holding a blank
  /// bar until the whole file has been read. The final emission is the
  /// complete waveform, which is also cached for the next time.
  Stream<List<double>> getWaveformProgressive(
    String filename,
    String path,
    Duration total,
  ) {
    final cached = _memoryCache[filename];
    if (cached != null) return Stream.value(cached);

    final existing = _progressive[filename];
    if (existing != null) return existing.stream;

    final controller = StreamController<List<double>>.broadcast();
    _progressive[filename] = controller;
    unawaited(() async {
      try {
        await _runProgressive(filename, path, total, controller);
      } finally {
        // Unregister before closing so a request that lands right after the
        // cache write starts a fresh controller and reads the cache, instead
        // of subscribing to this just-finished stream and receiving nothing.
        _progressive.remove(filename);
        if (!controller.isClosed) await controller.close();
      }
    }());
    return controller.stream;
  }

  Future<void> _runProgressive(
    String filename,
    String path,
    Duration total,
    StreamController<List<double>> controller,
  ) async {
    if (path.isEmpty || path.startsWith('http')) {
      controller.add(const []);
      return;
    }

    final cacheFile = await _cacheService.getWaveformCacheFile(filename);
    if (await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final List<dynamic> json = jsonDecode(content);
        final samples = json.cast<double>();
        _memoryCache[filename] = samples;
        controller.add(samples);
      } catch (e) {
        debugPrint('Error reading waveform cache: $e');
      }
      return;
    }

    final samples = await _extractWaveformProgressive(
      path,
      total,
      (peaks) {
        if (!controller.isClosed) controller.add(peaks);
      },
    );
    if (samples.isEmpty) return;
    _memoryCache[filename] = samples;
    if (!controller.isClosed) controller.add(samples);

    try {
      final cachePath = cacheFile.path;
      await _isolateWriteWaveformCache(cachePath, samples);
    } catch (e) {
      debugPrint('Error writing waveform cache: $e');
    }
  }

  Future<List<double>> _extractWaveformFast(String path) {
    return _extractWaveformStream(
      path: path,
      total: Duration.zero,
      onPartial: null,
    );
  }

  Future<List<double>> _extractWaveformProgressive(
    String path,
    Duration total,
    void Function(List<double>) onPartial,
  ) {
    return _extractWaveformStream(
      path: path,
      total: total,
      onPartial: onPartial,
    );
  }

  /// Streams 16-bit mono PCM directly from FFmpeg's output pipe without writing
  /// uncompressed temp files to disk or polling file sizes.
  Future<List<double>> _extractWaveformStream({
    required String path,
    required Duration total,
    void Function(List<double>)? onPartial,
  }) {
    return MediaDecodeGate.run(
      () => _runWaveformStreamDecode(
        path: path,
        total: total,
        onPartial: onPartial,
      ),
      priority: MediaDecodePriority.high,
    );
  }

  Future<List<double>> _runWaveformStreamDecode({
    required String path,
    required Duration total,
    void Function(List<double>)? onPartial,
  }) async {
    final targetSamples = targetWaveformSamples;
    final expectedBytes = total.inMilliseconds > 0
        ? (total.inMilliseconds * _pcmBytesPerSecond) ~/ 1000
        : (total.inSeconds > 0 ? total.inSeconds * _pcmBytesPerSecond : 0);

    if (FFmpegService.usesSystemProcess) {
      return _decodeViaSystemProcessPipe(
        path: path,
        targetSamples: targetSamples,
        expectedBytes: expectedBytes,
        onPartial: onPartial,
      );
    } else {
      return _decodeViaMobilePipeOrFallback(
        path: path,
        targetSamples: targetSamples,
        expectedBytes: expectedBytes,
        onPartial: onPartial,
      );
    }
  }

  /// Decodes directly from FFmpeg's stdout stream pipe on Desktop/Linux.
  /// 100% event-driven push, zero disk writes, zero polling.
  Future<List<double>> _decodeViaSystemProcessPipe({
    required String path,
    required int targetSamples,
    required int expectedBytes,
    void Function(List<double>)? onPartial,
  }) async {
    final args = [
      '-threads',
      '1',
      '-i',
      path,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '4000',
      '-f',
      's16le',
      '-',
    ];

    final process = await FFmpegService.instance.startFFmpeg(args);
    if (process == null) {
      debugPrint('FFmpegService: Failed to start ffmpeg process for streaming');
      return generateWaveformPlaceholderSamples(targetSamples);
    }

    final builder = BytesBuilder(copy: false);
    var lastEmittedBytes = 0;
    var lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
    const int emitThresholdBytes = 3200;

    final completer = Completer<void>();
    final sub = process.stdout.listen(
      (chunk) {
        builder.add(chunk);
        if (onPartial != null && expectedBytes > 0) {
          final currentLen = builder.length;
          final now = DateTime.now();
          if (currentLen - lastEmittedBytes >= emitThresholdBytes &&
              now.difference(lastEmitTime).inMilliseconds >= 32) {
            lastEmitTime = now;
            lastEmittedBytes = currentLen;
            final bytesSnapshot = builder.toBytes();
            final peaks = progressiveWaveformPeaksFromS16Bytes(
              bytesSnapshot,
              targetSamples,
              expectedBytes,
            );
            if (peaks.isNotEmpty) onPartial(peaks);
          }
        }
      },
      onError: (e) {
        debugPrint('Waveform pipe stream error: $e');
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );

    // Drain stderr in background so the process never blocks on full pipe buffer
    unawaited(process.stderr.drain().catchError((_) {}));

    final exitCode = await process.exitCode;
    await completer.future;
    await sub.cancel();

    if (exitCode != 0) {
      debugPrint('FFmpeg streaming exited with code $exitCode');
      return generateWaveformPlaceholderSamples(targetSamples);
    }

    final fullBytes = builder.toBytes();
    if (fullBytes.length < 2) {
      return generateWaveformPlaceholderSamples(targetSamples);
    }

    return extractWaveformPeaksFromS16Bytes(fullBytes, targetSamples);
  }

  /// Decodes via named pipe on mobile platforms (iOS/Android), or falls back to temp file.
  Future<List<double>> _decodeViaMobilePipeOrFallback({
    required String path,
    required int targetSamples,
    required int expectedBytes,
    void Function(List<double>)? onPartial,
  }) async {
    String? pipePath;
    try {
      pipePath = await FFmpegKitConfig.registerNewFFmpegPipe();
    } catch (_) {
      pipePath = null;
    }

    if (pipePath != null) {
      try {
        final args = [
          '-threads',
          '1',
          '-i',
          path,
          '-vn',
          '-ac',
          '1',
          '-ar',
          '4000',
          '-f',
          's16le',
          '-y',
          pipePath,
        ];

        final builder = BytesBuilder(copy: false);
        var lastEmittedBytes = 0;
        var lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
        const int emitThresholdBytes = 3200;

        final sessionCompleter = Completer<bool>();
        await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
          final returnCode = await session.getReturnCode();
          sessionCompleter.complete(returnCode?.isValueSuccess() ?? false);
        });

        final pipeFile = File(pipePath);
        final stream = pipeFile.openRead();

        await for (final chunk in stream) {
          builder.add(chunk);
          if (onPartial != null && expectedBytes > 0) {
            final currentLen = builder.length;
            final now = DateTime.now();
            if (currentLen - lastEmittedBytes >= emitThresholdBytes &&
                now.difference(lastEmitTime).inMilliseconds >= 32) {
              lastEmitTime = now;
              lastEmittedBytes = currentLen;
              final bytesSnapshot = builder.toBytes();
              final peaks = progressiveWaveformPeaksFromS16Bytes(
                bytesSnapshot,
                targetSamples,
                expectedBytes,
              );
              if (peaks.isNotEmpty) onPartial(peaks);
            }
          }
        }

        final isSuccess = await sessionCompleter.future;
        if (!isSuccess) {
          return generateWaveformPlaceholderSamples(targetSamples);
        }

        final fullBytes = builder.toBytes();
        if (fullBytes.length < 2) {
          return generateWaveformPlaceholderSamples(targetSamples);
        }
        return extractWaveformPeaksFromS16Bytes(fullBytes, targetSamples);
      } catch (e) {
        debugPrint('Mobile pipe decode error: $e');
      } finally {
        try {
          await FFmpegKitConfig.closeFFmpegPipe(pipePath);
        } catch (_) {}
      }
    }

    // Fallback if named pipe unsupported
    return _decodeWithTempFileFallback(
      path: path,
      targetSamples: targetSamples,
    );
  }

  Future<List<double>> _decodeWithTempFileFallback({
    required String path,
    required int targetSamples,
  }) async {
    File? raw;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final outputPath = p.join(
        tempDir.path,
        'waveform_${DateTime.now().microsecondsSinceEpoch}.raw',
      );

      final args = [
        '-threads',
        '1',
        '-i',
        path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '4000',
        '-f',
        's16le',
        '-y',
        outputPath,
      ];

      final result = await FFmpegService.instance.executeFFmpeg(args);
      if (!result.isSuccess) {
        return generateWaveformPlaceholderSamples(targetSamples);
      }

      raw = File(outputPath);
      if (!await raw.exists()) {
        return generateWaveformPlaceholderSamples(targetSamples);
      }

      final bytes = await raw.readAsBytes();
      return extractWaveformPeaksFromS16Bytes(bytes, targetSamples);
    } catch (e) {
      debugPrint('Fallback waveform extraction failed: $e');
      return generateWaveformPlaceholderSamples(targetSamples);
    } finally {
      try {
        if (raw != null && await raw.exists()) await raw.delete();
      } catch (_) {}
    }
  }

  void dispose() {}
}

Future<void> _isolateWriteWaveformCache(String path, List<double> samples) {
  return Isolate.run(() => writeWaveformCacheFile(path, samples));
}

void writeWaveformCacheFile(String path, List<double> samples) {
  File(path).writeAsStringSync(jsonEncode(samples));
}

/// Buckets 16-bit mono PCM [bytes] into [targetSamples] peak bars.
///
/// Shared by the full and the progressive paths; both run off the UI isolate
/// and neither touches the file here — the caller provides the byte buffer.
List<double> extractWaveformPeaksFromS16Bytes(
  Uint8List bytes,
  int targetSamples,
) {
  if (bytes.length < 2) {
    return generateWaveformPlaceholderSamples(targetSamples);
  }

  final usable = bytes.length - (bytes.length % 2);
  final Int16List pcm;
  if (bytes.offsetInBytes % 2 == 0) {
    pcm = Int16List.view(bytes.buffer, bytes.offsetInBytes, usable ~/ 2);
  } else {
    pcm = Int16List.view(
      Uint8List.fromList(bytes.sublist(0, usable)).buffer,
    );
  }

  if (pcm.isEmpty) {
    return generateWaveformPlaceholderSamples(targetSamples);
  }

  final samples = List<double>.filled(targetSamples, 0);
  final samplesPerPeak = (pcm.length / targetSamples).ceil();

  for (var i = 0; i < targetSamples; i++) {
    final start = i * samplesPerPeak;
    final end = start + samplesPerPeak;
    var maxAmp = 0.0;
    for (var j = start; j < end && j < pcm.length; j++) {
      final amp = pcm[j].abs() / 32768.0;
      if (amp > maxAmp) maxAmp = amp;
    }
    samples[i] = maxAmp.clamp(0.0, 1.0);
  }

  return samples;
}

/// Buckets the decoded-so-far PCM into the first [targetSamples] * (bytes /
/// [expectedBytes]) bars, so the waveform paints left-to-right as the file
/// decodes instead of waiting for the whole read.
List<double> progressiveWaveformPeaksFromS16Bytes(
  Uint8List bytes,
  int targetSamples,
  int expectedBytes,
) {
  final fraction =
      expectedBytes > 0 ? (bytes.length / expectedBytes).clamp(0.0, 1.0) : 1.0;
  final filled = (fraction * targetSamples).round().clamp(1, targetSamples);
  return extractWaveformPeaksFromS16Bytes(bytes, filled);
}

List<double> generateWaveformPlaceholderSamples(int count) {
  final samples = <double>[];
  final random = DateTime.now().millisecond;
  for (var i = 0; i < count; i++) {
    final base = 0.05 + (i % 11) * 0.08;
    final variation = ((random * (i + 1)) % 250) / 1000.0;
    final value = (base + variation).clamp(0.0, 1.0);
    samples.add(value);
  }
  return samples;
}

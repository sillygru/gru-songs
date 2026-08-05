import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_service.dart';
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

  /// Fast check if the waveform for [filename] is already cached on disk.
  Future<bool> isWaveformCached(String filename) async {
    if (filename.isEmpty) return false;
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
    final cacheFile = await _cacheService.getWaveformCacheFile(filename);
    if (await cacheFile.exists()) {
      try {
        final content = await cacheFile.readAsString();
        final List<dynamic> json = jsonDecode(content);
        return json.cast<double>();
      } catch (e) {
        debugPrint('Error reading waveform cache: $e');
      }
    }

    final samples = await _extractWaveformFast(path);
    if (samples.isEmpty) return const [];

    try {
      final cachePath = cacheFile.path;
      await Isolate.run(() => writeWaveformCacheFile(cachePath, samples));
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
        controller.add(json.cast<double>());
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
    if (!controller.isClosed) controller.add(samples);

    try {
      final cachePath = cacheFile.path;
      await Isolate.run(() => writeWaveformCacheFile(cachePath, samples));
    } catch (e) {
      debugPrint('Error writing waveform cache: $e');
    }
  }

  Future<List<double>> _extractWaveformFast(String path) async {
    return _extractWaveformDirect(path, targetWaveformSamples);
  }

  /// Direct waveform extraction without delay-inducing filters.
  ///
  /// Uses a single FFmpeg thread and 16-bit mono PCM so decode stays cheap
  /// enough not to underrun playback on the same device.
  Future<List<double>> _extractWaveformDirect(
    String path,
    int targetSamples,
  ) async {
    File? raw;
    try {
      final outputPath = await _prepareTempOutputPath();
      final decodeSucceeded = await _decodeToPcmFile(path, outputPath);
      if (!decodeSucceeded) {
        debugPrint('FFmpeg failed to extract waveform');
        return generateWaveformPlaceholderSamples(targetSamples);
      }

      raw = File(outputPath);
      if (!await raw.exists()) {
        return generateWaveformPlaceholderSamples(targetSamples);
      }

      final rawPath = raw.path;
      return await Isolate.run(
        () => extractWaveformPeaksFromS16File(rawPath, targetSamples),
      );
    } catch (e) {
      debugPrint('Error in direct waveform extraction: $e');
      return generateWaveformPlaceholderSamples(targetSamples);
    } finally {
      try {
        if (raw != null && await raw.exists()) await raw.delete();
      } catch (_) {}
    }
  }

  /// The single source of the waveform decode settings, so the direct and the
  /// progressive paths cannot drift apart: one FFmpeg thread to keep headroom
  /// for the audio callback, 16-bit mono PCM at 4 kHz, no delay-inducing
  /// filters.
  static List<String> _waveformDecodeArgs(String path, String outputPath) {
    return [
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
  }

  /// Decodes [path] to raw 16-bit mono PCM at the waveform sample rate.
  ///
  /// Only the FFmpeg session is serialized through the shared gate: a waveform
  /// must not decode the same file while a beat analysis is mid-decode, on top
  /// of just_audio buffering it. High priority because it is the seek bar the
  /// user is looking at: any still-queued beat prefetch yields to it.
  Future<bool> _decodeToPcmFile(String path, String outputPath) {
    return MediaDecodeGate.run(
      () async {
        final session = await FFmpegKit.executeWithArguments(
          _waveformDecodeArgs(path, outputPath),
        );
        final returnCode = await session.getReturnCode();
        return ReturnCode.isSuccess(returnCode);
      },
      priority: MediaDecodePriority.high,
    );
  }

  /// Decodes [path] while yielding partial peak lists as the PCM grows.
  ///
  /// The decode runs inside the shared gate; meanwhile a timer watches the
  /// temp file, and each time it has grown it buckets the bytes decoded so far
  /// into the *first* [targetWaveformSamples] fraction of the bars (the song
  /// duration gives the expected final byte count). Returns the complete
  /// waveform once the session finishes.
  Future<List<double>> _extractWaveformProgressive(
    String path,
    Duration total,
    void Function(List<double>) onPartial,
  ) async {
    final targetSamples = targetWaveformSamples;
    final expectedBytes =
        total.inSeconds > 0 ? total.inSeconds * _pcmBytesPerSecond : 0;

    File? raw;
    try {
      final outputPath = await _prepareTempOutputPath();
      final rawFile = File(outputPath);
      raw = rawFile;
      var lastYieldedBytes = 0;

      final decodeSucceeded = await MediaDecodeGate.run(
        () async {
          final session = await FFmpegKit.executeWithArguments(
            _waveformDecodeArgs(path, outputPath),
          );

          Timer? poller;
          if (expectedBytes > 0) {
            // A tick is skipped while the previous one is still extracting,
            // so overlapping 250 ms ticks cannot pile up isolate work.
            var yielding = false;
            poller = Timer.periodic(const Duration(milliseconds: 250), (_) {
              if (yielding) return;
              yielding = true;
              unawaited(() async {
                try {
                  final length = await rawFile.length();
                  if (length <= lastYieldedBytes) return;
                  lastYieldedBytes = length;
                  final rawPath = rawFile.path;
                  final peaks = await Isolate.run(
                    () => progressiveWaveformPeaksFromS16File(
                      rawPath,
                      targetSamples,
                      expectedBytes,
                    ),
                  );
                  if (peaks.isNotEmpty) onPartial(peaks);
                } catch (_) {
                  // A read racing the session's final flush is not worth
                  // surfacing; the final extraction below is authoritative.
                } finally {
                  yielding = false;
                }
              }());
            });
          }

          try {
            final returnCode = await session.getReturnCode();
            return ReturnCode.isSuccess(returnCode);
          } finally {
            poller?.cancel();
          }
        },
        priority: MediaDecodePriority.high,
      );

      if (!decodeSucceeded) {
        debugPrint('FFmpeg failed to extract waveform');
        return generateWaveformPlaceholderSamples(targetSamples);
      }
      if (!await rawFile.exists() || await rawFile.length() == 0) {
        return generateWaveformPlaceholderSamples(targetSamples);
      }

      final rawPath = rawFile.path;
      return await Isolate.run(
        () => extractWaveformPeaksFromS16File(rawPath, targetSamples),
      );
    } catch (e) {
      debugPrint('Error in progressive waveform extraction: $e');
      return generateWaveformPlaceholderSamples(targetSamples);
    } finally {
      try {
        if (raw != null && await raw.exists()) await raw.delete();
      } catch (_) {}
    }
  }

  /// Creates the temp decode directory and a fresh output path for it.
  Future<String> _prepareTempOutputPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return p.join(
      tempDir.path,
      'waveform_${DateTime.now().microsecondsSinceEpoch}.raw',
    );
  }

  void dispose() {}
}

void writeWaveformCacheFile(String path, List<double> samples) {
  File(path).writeAsStringSync(jsonEncode(samples));
}

/// Reads PCM and buckets peaks entirely off the UI isolate.
List<double> extractWaveformPeaksFromS16File(String path, int targetSamples) {
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 2) {
      return generateWaveformPlaceholderSamples(targetSamples);
    }
    return extractWaveformPeaksFromS16Bytes(bytes, targetSamples);
  } catch (e) {
    debugPrint('Error extracting peaks from PCM: $e');
    return generateWaveformPlaceholderSamples(targetSamples);
  }
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

/// File-reading twin of [progressiveWaveformPeaksFromS16Bytes], for Isolate.run.
List<double> progressiveWaveformPeaksFromS16File(
  String path,
  int targetSamples,
  int expectedBytes,
) {
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 2) return const [];
    return progressiveWaveformPeaksFromS16Bytes(
      bytes,
      targetSamples,
      expectedBytes,
    );
  } catch (_) {
    return const [];
  }
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

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

class WaveformService {
  final CacheService _cacheService;

  WaveformService(this._cacheService);

  /// One decode at a time. Parallel FFmpeg sessions fight the audio thread.
  Future<void> _chain = Future.value();

  final Map<String, Future<List<double>>> _inFlight = {};

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

  Future<List<double>> _extractWaveformFast(String path) async {
    return _extractWaveformDirect(path, 2000);
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
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final outputPath = p.join(
        tempDir.path,
        'waveform_${DateTime.now().microsecondsSinceEpoch}.raw',
      );

      // -threads 1: keep CPU headroom for the audio callback
      // -ac 1 / -ar 4000 / s16le: small PCM buffer, no lookahead filters
      final session = await FFmpegKit.executeWithArguments([
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
      ]);

      final returnCode = await session.getReturnCode();
      raw = File(outputPath);
      if (!ReturnCode.isSuccess(returnCode)) {
        debugPrint('FFmpeg failed to extract waveform');
        return generateWaveformPlaceholderSamples(targetSamples);
      }

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
  } catch (e) {
    debugPrint('Error extracting peaks from PCM: $e');
    return generateWaveformPlaceholderSamples(targetSamples);
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

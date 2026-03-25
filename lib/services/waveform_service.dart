import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'cache_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class WaveformService {
  final CacheService _cacheService;

  WaveformService(this._cacheService);

  Future<List<double>> getWaveform(String filename, String path) async {
    if (path.isEmpty || path.startsWith('http')) return [];

    final cacheFile = await _cacheService.getV3File('waveform_$filename.json');
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
    if (samples.isEmpty) return [];

    try {
      await cacheFile.writeAsString(jsonEncode(samples));
    } catch (e) {
      debugPrint('Error writing waveform cache: $e');
    }

    return samples;
  }

  Future<List<double>> _extractWaveformFast(String path) async {
    // Direct PCM extraction without filters that introduce delay/lookahead
    return await _extractWaveformDirect(path, 2000);
  }

  /// Direct waveform extraction without delay-inducing filters.
  /// Uses raw PCM output with no audio filters to ensure sample-accurate alignment.
  Future<List<double>> _extractWaveformDirect(
      String path, int targetSamples) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final outputPath = p.join(tempDir.path,
          'waveform_${DateTime.now().millisecondsSinceEpoch}.raw');

      // Use direct PCM extraction without any filters that introduce lookahead/delay.
      // -ac 1: Convert to mono (simple averaging, no delay)
      // -ar 8000: Downsample to 8kHz for manageable data size
      // -f f32le: 32-bit float little-endian PCM (no compression/processing)
      // -vn: Disable video stream processing
      // No -af filters: Avoid compand, volumedetect, astats which add lookahead
      final session = await FFmpegKit.executeWithArguments([
        '-i',
        path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '8000',
        '-f',
        'f32le',
        '-y',
        outputPath
      ]);

      final returnCode = await session.getReturnCode();
      if (returnCode == null || !returnCode.isValueSuccess()) {
        debugPrint('FFmpeg failed to extract waveform');
        return _generatePlaceholderSamples(targetSamples);
      }

      final file = File(outputPath);
      if (!await file.exists()) {
        return _generatePlaceholderSamples(targetSamples);
      }

      final bytes = await file.readAsBytes();
      await file.delete();

      // Extract peaks directly from raw PCM data
      final samples = _extractPeaksFromPcm(bytes, targetSamples);
      return samples;
    } catch (e) {
      debugPrint('Error in direct waveform extraction: $e');
      return _generatePlaceholderSamples(targetSamples);
    }
  }

  List<double> _extractPeaksFromPcm(Uint8List bytes, int targetSamples) {
    try {
      final floatData = Float32List.view(bytes.buffer);
      final samples = <double>[];
      final samplesPerPeak = (floatData.length / targetSamples).ceil();

      for (int i = 0; i < targetSamples; i++) {
        final start = i * samplesPerPeak;
        final end = start + samplesPerPeak;
        double maxAmp = 0;
        for (int j = start; j < end && j < floatData.length; j++) {
          final amp = floatData[j].abs();
          if (amp > maxAmp) maxAmp = amp;
        }
        // Simple linear scaling
        maxAmp = maxAmp * 0.9;
        // Clamp to reasonable maximum
        maxAmp = maxAmp.clamp(0.0, 64.0) / 64.0;
        samples.add(maxAmp.clamp(0.0, 1.0));
      }

      if (samples.isEmpty) {
        return _generatePlaceholderSamples(targetSamples);
      }

      return samples;
    } catch (e) {
      debugPrint('Error extracting peaks from PCM: $e');
      return _generatePlaceholderSamples(targetSamples);
    }
  }

  List<double> _generatePlaceholderSamples(int count) {
    final samples = <double>[];
    final random = DateTime.now().millisecond;
    for (int i = 0; i < count; i++) {
      // Simple linear scaling
      final base = 0.05 + (i % 11) * 0.08;
      final variation = ((random * (i + 1)) % 250) / 1000.0;
      final value = (base + variation).clamp(0.0, 1.0);
      final enhancedValue = value * 0.9;
      final clampedValue = enhancedValue.clamp(0.0, 64.0) / 64.0;
      samples.add(clampedValue.clamp(0.0, 1.0));
    }
    return samples;
  }

  void dispose() {}
}

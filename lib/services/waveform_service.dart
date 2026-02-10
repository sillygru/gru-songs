import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
    try {
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final outputPath = p.join(tempDir.path,
          'waveform_${DateTime.now().millisecondsSinceEpoch}.csv');

      const targetSamples = 2000;

      // Optimized FFmpeg command for faster waveform extraction
      // -vn: no video, -ac 1: mono, -f csv: output as CSV
      // -af: audio filter to generate peak waveform data with reduced sample rate
      final command = '-i "$path" '
          '-vn -ac 1 -f csv '
          '-af "compand,astats=metadata=1:reset=1,selectivecolor=color=white,ametadata=select=key:file=$outputPath" '
          '-y "$outputPath"';
      final session = await FFmpegKit.executeAsync(command);
      final returnCode = await session.getReturnCode();

      if (!await File(outputPath).exists()) {
        // Fallback to a faster raw extraction method if the advanced method fails
        return await _extractWaveformUltraFast(path, targetSamples);
      }

      final content = await File(outputPath).readAsString();
      await File(outputPath).delete(); // Clean up

      // Parse the CSV output to extract amplitude values
      final samples = _parseCsvWaveformData(content, targetSamples);
      if (samples.isNotEmpty) {
        return samples;
      }

      // If CSV parsing fails, fall back to ultra-fast method
      return await _extractWaveformUltraFast(path, targetSamples);
    } catch (e) {
      debugPrint('Error extracting waveform with FFmpeg for $path: $e');
      return _generatePlaceholderSamples(2000);
    }
  }

  /// Ultra-fast waveform extraction using minimal processing
  Future<List<double>> _extractWaveformUltraFast(
      String path, int targetSamples) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(supportDir.path, 'waveform_temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final outputPath = p.join(tempDir.path,
          'waveform_${DateTime.now().millisecondsSinceEpoch}.raw');

      final session = await FFmpegKit.executeWithArguments([
        '-i',
        path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '4000',
        '-f',
        'f32le',
        '-af',
        'volumedetect',
        '-y',
        outputPath
      ]);

      final returnCode = await session.getReturnCode();

      final file = File(outputPath);
      if (!await file.exists()) {
        return _generatePlaceholderSamples(targetSamples);
      }

      final bytes = await file.readAsBytes();
      await file.delete();

      // Extract peaks from raw data more efficiently
      final samples = _extractPeaksFromPcm(bytes, targetSamples);
      return samples;
    } catch (e) {
      debugPrint('Error in ultra-fast waveform extraction: $e');
      return _generatePlaceholderSamples(targetSamples);
    }
  }

  /// Alternative ultra-fast method using stat-based approach
  List<double> _parseCsvWaveformData(String csvContent, int targetSamples) {
    try {
      final lines = csvContent.split('\n');
      final values = <double>[];

      // Extract numeric values from CSV
      for (final line in lines) {
        if (line.trim().isNotEmpty && !line.startsWith('#')) {
          final parts = line.split(',');
          for (final part in parts) {
            final cleanPart = part.trim().replaceAll(RegExp(r'[^\d.-]'), '');
            if (cleanPart.isNotEmpty) {
              final numValue = double.tryParse(cleanPart);
              if (numValue != null) {
                var normalizedValue = numValue.abs();
                // Simple linear scaling
                normalizedValue = normalizedValue * 0.9;
                // Clamp to reasonable maximum
                normalizedValue = normalizedValue.clamp(0.0, 64.0) / 64.0;
                values.add(normalizedValue.clamp(0.0, 1.0));
              }
            }
          }
        }
      }

      if (values.isEmpty) return [];

      // Resample to target number of samples
      return _resampleValues(values, targetSamples);
    } catch (e) {
      debugPrint('Error parsing CSV waveform data: $e');
      return [];
    }
  }

  /// Efficient resampling of values to target count
  List<double> _resampleValues(List<double> values, int targetCount) {
    if (values.length <= targetCount) {
      // Pad with zeros if we have fewer values than needed
      final result = List<double>.from(values);
      while (result.length < targetCount) {
        result.add(0.0);
      }
      return result.take(targetCount).toList();
    }

    // Downsample by taking average/max of chunks
    final result = <double>[];
    final chunkSize = values.length ~/ targetCount;

    for (int i = 0; i < targetCount; i++) {
      final start = i * chunkSize;
      final end = (i + 1) * chunkSize;

      if (start < values.length) {
        final endIdx = end > values.length ? values.length : end;
        double maxVal = 0.0;

        for (int j = start; j < endIdx; j++) {
          if (values[j] > maxVal) maxVal = values[j];
        }

        // Simple linear scaling
        maxVal = maxVal * 0.9;
        // Clamp to reasonable maximum
        maxVal = maxVal.clamp(0.0, 64.0) / 64.0;
        result.add(maxVal.clamp(0.0, 1.0));
      } else {
        result.add(0.0);
      }
    }

    return result;
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

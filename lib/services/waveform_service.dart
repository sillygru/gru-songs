import 'dart:convert';
import 'dart:io';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'cache_service.dart';
import 'package:flutter/foundation.dart';

class WaveformService {
  final CacheService _cacheService;
  final PlayerController _extractionController = PlayerController();

  WaveformService(this._cacheService);

  Future<List<double>> getWaveform(String filename, String path) async {
    // Only support local files
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

    // Extract if not cached
    try {
      final file = File(path);
      if (!await file.exists()) return [];

      final samples = await _extractionController.extractWaveformData(
        path: path,
        noOfSamples: 2000,
      );
      
      if (samples.isEmpty) return [];

      final clampedSamples = samples.map((v) => v.clamp(0.0, 1.0)).toList();
      
      // Cache it
      await cacheFile.writeAsString(jsonEncode(clampedSamples));
      return clampedSamples;
    } catch (e) {
      debugPrint('Error extracting waveform for $filename: $e');
      return [];
    }
  }

  void dispose() {
    _extractionController.dispose();
  }
}

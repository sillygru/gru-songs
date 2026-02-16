import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

class ColorExtractionService {
  static const double _minSaturation = 0.15;
  static const double _minLightness = 0.10;
  static const double _maxLightness = 0.90;

  static Map<String, int> _colorCache = {};
  static File? _cacheFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      _cacheFile = File(p.join(appSupportDir.path, 'color_cache.json'));

      if (await _cacheFile!.exists()) {
        final jsonString = await _cacheFile!.readAsString();
        final Map<String, dynamic> json = jsonDecode(jsonString);
        _colorCache = json.map((key, value) => MapEntry(key, value as int));
        debugPrint('ColorExtractionService: Loaded ${_colorCache.length} cached colors');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('ColorExtractionService init error: $e');
      _initialized = true;
    }
  }

  static Future<Color?> extractColor(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    await init();

    if (_colorCache.containsKey(imagePath)) {
      return Color(_colorCache[imagePath]!);
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final imageBytes = await file.readAsBytes();
      final colorInt = await compute(_extractColorInIsolate, imageBytes);

      if (colorInt != null) {
        _colorCache[imagePath] = colorInt;
        await _saveCacheToDisk();
        return Color(colorInt);
      }
      return null;
    } catch (e) {
      debugPrint('Error extracting color: $e');
      return null;
    }
  }

  static Future<void> _saveCacheToDisk() async {
    if (_cacheFile == null) return;
    try {
      final jsonString = jsonEncode(_colorCache);
      await _cacheFile!.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving color cache: $e');
    }
  }

  static Future<void> clearCache() async {
    _colorCache.clear();
    if (_cacheFile != null && await _cacheFile!.exists()) {
      await _cacheFile!.delete();
    }
  }

  static Future<int> getCacheSize() async {
    if (_cacheFile == null || !await _cacheFile!.exists()) return 0;
    return await _cacheFile!.length();
  }
}

class _ColorCandidate {
  final int color;
  final int population;

  _ColorCandidate(this.color, this.population);
}

int? _extractColorInIsolate(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final resized = img.copyResize(image, width: 64, height: 64);

    final Map<int, int> colorCounts = {};
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final colorInt = (0xFF << 24) | (r << 16) | (g << 8) | b;
        colorCounts[colorInt] = (colorCounts[colorInt] ?? 0) + 1;
      }
    }

    final candidates = colorCounts.entries
        .map((e) => _ColorCandidate(e.key, e.value))
        .toList();

    final vibrantCandidates = candidates.where((c) {
      final color = Color(c.color);
      final hsl = HSLColor.fromColor(color);
      return hsl.saturation >= 0.3 && 
             hsl.lightness >= 0.2 && 
             hsl.lightness <= 0.8;
    }).toList();

    if (vibrantCandidates.isNotEmpty) {
      vibrantCandidates.sort((a, b) {
        final satA = HSLColor.fromColor(Color(a.color)).saturation;
        final satB = HSLColor.fromColor(Color(b.color)).saturation;
        return satB.compareTo(satA);
      });
      return vibrantCandidates.first.color;
    }

    candidates.sort((a, b) => b.population.compareTo(a.population));
    final dominant = candidates.firstOrNull;
    if (dominant != null && _isValidColorInt(dominant.color)) {
      return dominant.color;
    }

    final validColors = candidates.where((c) => _isValidColorInt(c.color)).toList();
    if (validColors.isEmpty) return null;

    validColors.sort((a, b) {
      final scoreA = _calculateColorScore(a);
      final scoreB = _calculateColorScore(b);
      return scoreB.compareTo(scoreA);
    });

    return validColors.first.color;
  } catch (e) {
    debugPrint('Error in isolate color extraction: $e');
    return null;
  }
}

bool _isValidColorInt(int colorInt) {
  final color = Color(colorInt);
  final hsl = HSLColor.fromColor(color);
  return hsl.saturation >= ColorExtractionService._minSaturation &&
      hsl.lightness >= ColorExtractionService._minLightness &&
      hsl.lightness <= ColorExtractionService._maxLightness;
}

double _calculateColorScore(_ColorCandidate candidate) {
  final color = Color(candidate.color);
  final hsl = HSLColor.fromColor(color);
  final saturationScore = hsl.saturation;
  final populationNormalized = math.min(candidate.population / 500.0, 1.0);
  return (saturationScore * 0.8) + (populationNormalized * 0.2);
}

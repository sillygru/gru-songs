import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ColorExtractionService {
  static const double _minSaturation = 0.2;
  static const double _minLightness = 0.15;
  static const double _maxLightness = 0.85;

  static Future<Color?> extractColor(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final imageProvider = FileImage(file);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 12,
      );

      final allColors = <PaletteColor>[
        if (paletteGenerator.vibrantColor != null)
          paletteGenerator.vibrantColor!,
        if (paletteGenerator.lightVibrantColor != null)
          paletteGenerator.lightVibrantColor!,
        if (paletteGenerator.darkVibrantColor != null)
          paletteGenerator.darkVibrantColor!,
        if (paletteGenerator.dominantColor != null)
          paletteGenerator.dominantColor!,
      ];

      final filteredColors = allColors.where(_isValidColor).toList();

      if (filteredColors.isEmpty) {
        return _findBestColorFromAll(paletteGenerator.paletteColors);
      }

      filteredColors.sort((a, b) {
        final scoreA = _calculateColorScore(a);
        final scoreB = _calculateColorScore(b);
        return scoreB.compareTo(scoreA);
      });

      return filteredColors.first.color;
    } catch (e) {
      debugPrint('Error extracting color: $e');
      return null;
    }
  }

  static bool _isValidColor(PaletteColor paletteColor) {
    final color = paletteColor.color;
    final hsl = HSLColor.fromColor(color);
    return hsl.saturation >= _minSaturation &&
        hsl.lightness >= _minLightness &&
        hsl.lightness <= _maxLightness;
  }

  static double _calculateColorScore(PaletteColor paletteColor) {
    final color = paletteColor.color;
    final hsl = HSLColor.fromColor(color);
    final population = paletteColor.population;

    final saturationScore = hsl.saturation;
    final populationNormalized = math.min(population / 1000.0, 1.0);

    return (saturationScore * 0.6) + (populationNormalized * 0.4);
  }

  static Color? _findBestColorFromAll(List<PaletteColor> paletteColors) {
    final validColors = paletteColors.where(_isValidColor).toList();

    if (validColors.isEmpty) return null;

    validColors.sort((a, b) {
      final scoreA = _calculateColorScore(a);
      final scoreB = _calculateColorScore(b);
      return scoreB.compareTo(scoreA);
    });

    return validColors.first.color;
  }
}

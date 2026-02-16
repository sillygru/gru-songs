import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ColorExtractionService {
  static const double _minSaturation = 0.15;
  static const double _minLightness = 0.10;
  static const double _maxLightness = 0.90;

  static Future<Color?> extractColor(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final imageProvider = FileImage(file);

      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 18,
      );

      // 1. Priority: Vibrant Colors (The "Subject")
      // The Palette library is designed to put subject/accent colors
      // into the 'Vibrant' slots. We check these first.
      final vibrantCandidates = <PaletteColor>[
        if (paletteGenerator.vibrantColor != null)
          paletteGenerator.vibrantColor!,
        if (paletteGenerator.darkVibrantColor != null)
          paletteGenerator.darkVibrantColor!,
        if (paletteGenerator.lightVibrantColor != null)
          paletteGenerator.lightVibrantColor!,
      ];

      final validVibrant = vibrantCandidates.where(_isValidColor).toList();

      if (validVibrant.isNotEmpty) {
        // If we found vibrant colors, pick the most saturated one immediately.
        // We do NOT compare population here, preventing the large background
        // from winning just because it's bigger.
        validVibrant.sort((a, b) {
          final satA = HSLColor.fromColor(a.color).saturation;
          final satB = HSLColor.fromColor(b.color).saturation;
          return satB.compareTo(satA);
        });
        return validVibrant.first.color;
      }

      // 2. Fallback: Dominant Color (The "Background")
      // Only use the dominant (largest area) color if no vibrant subject was found.
      if (paletteGenerator.dominantColor != null &&
          _isValidColor(paletteGenerator.dominantColor!)) {
        return paletteGenerator.dominantColor!.color;
      }

      // 3. Last Resort: Score all colors
      return _findBestColorFromAll(paletteGenerator.paletteColors);
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
    // Cap population influence at 5000 pixels.
    // This stops massive backgrounds from getting an infinitely high score.
    final populationNormalized = math.min(population / 5000.0, 1.0);

    // New Weighting: 80% Saturation, 20% Population.
    // This heavily favors "colorfulness" over "size".
    return (saturationScore * 0.8) + (populationNormalized * 0.2);
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:wispie/domain/services/cover_palette.dart';
import 'package:wispie/services/color_extraction_service.dart';

import 'test_helpers.dart';

/// Signed shortest distance between two hues, in degrees.
double hueDelta(double a, double b) {
  final diff = (a - b).abs() % 360;
  return diff > 180 ? 360 - diff : diff;
}

/// Colours round-trip through 8-bit channels, so a lightness band boundary can
/// land a fraction of a step outside it.
const double kQuantum = 1 / 255;

double hueOf(Color color) => HSLColor.fromColor(color).hue;
double satOf(Color color) => HSLColor.fromColor(color).saturation;
double lightOf(Color color) => HSLColor.fromColor(color).lightness;

void main() {
  group('selectAccent', () {
    // The clusters k-means actually finds in the YOASOBI "E-SIDE 2" cover:
    // a light grey field covering ~73% of the artwork, and the blue pixel art.
    final eSide2 = [
      const Swatch(color: Color(0xFFDADADB), population: 7273),
      const Swatch(color: Color(0xFF5E5AF4), population: 1414),
      const Swatch(color: Color(0xFFCECFD7), population: 700),
      const Swatch(color: Color(0xFF8987E3), population: 329),
      const Swatch(color: Color(0xFFB2B1E3), population: 284),
    ];

    test('picks the colourful region over a larger neutral one', () {
      final result = selectAccent(eSide2);

      expect(result.isNeutral, isFalse);
      // The cover is blue; the accent must be blue, not the grey background and
      // not an average of the two.
      expect(hueDelta(hueOf(result.accent), 241.6), lessThan(15));
    });

    test('never invents a hue for a near-neutral cover', () {
      // Every swatch is an off-white or grey with the faint warm cast that JPEG
      // compression and scanned artwork leave behind. Saturating these into a
      // confident colour is what turned a white-and-blue cover salmon.
      final result = selectAccent(const [
        Swatch(color: Color(0xFFE9E7E4), population: 6000),
        Swatch(color: Color(0xFFB3B1AE), population: 2000),
        Swatch(color: Color(0xFF2A2928), population: 1000),
      ]);

      expect(result.isNeutral, isTrue);
      expect(result.accent, kNeutralAccent);
      expect(satOf(result.accent), lessThan(kMinChroma));
    });

    test('treats pure greyscale artwork as neutral', () {
      final result = selectAccent(const [
        Swatch(color: Color(0xFF000000), population: 4000),
        Swatch(color: Color(0xFF808080), population: 3000),
        Swatch(color: Color(0xFFFFFFFF), population: 3000),
      ]);

      expect(result.isNeutral, isTrue);
    });

    test('ignores hue carried by blown-out and crushed swatches', () {
      // A near-white pixel with a 6% cast and a near-black one with a blue cast
      // both report a hue, but neither is a colour anyone can see.
      final result = selectAccent(const [
        Swatch(color: Color(0xFFFCF8F5), population: 5000),
        Swatch(color: Color(0xFF03040A), population: 5000),
      ]);

      expect(result.isNeutral, isTrue);
    });

    test('a small saturated region still beats a huge desaturated one', () {
      final result = selectAccent(const [
        Swatch(color: Color(0xFF6E6A66), population: 9500),
        Swatch(color: Color(0xFF00B34A), population: 500),
      ]);

      expect(result.isNeutral, isFalse);
      expect(hueDelta(hueOf(result.accent), hueOf(const Color(0xFF00B34A))),
          lessThan(10));
    });

    test('but a stray speck does not', () {
      final result = selectAccent(const [
        Swatch(color: Color(0xFFCC3355), population: 9000),
        Swatch(color: Color(0xFF00B34A), population: 12),
      ]);

      expect(hueDelta(hueOf(result.accent), hueOf(const Color(0xFFCC3355))),
          lessThan(10));
    });

    test('is deterministic for the same swatches', () {
      expect(selectAccent(eSide2).accent, selectAccent(eSide2).accent);
    });

    test('ranks the returned swatches by population', () {
      final result = selectAccent(eSide2);
      expect(result.swatches.first, const Color(0xFFDADADB));
      expect(result.swatches.length, eSide2.length);
    });

    test('handles an empty palette', () {
      final result = selectAccent(const []);
      expect(result.isNeutral, isTrue);
      expect(result.accent, kNeutralAccent);
    });
  });

  group('normalizeAccent', () {
    test('lifts a dark cover colour into the legible band, keeping its hue',
        () {
      const dark = Color(0xFF0D1B4A);
      final accent = normalizeAccent(dark);

      expect(hueDelta(hueOf(accent), hueOf(dark)), lessThan(1));
      expect(lightOf(accent), greaterThan(kAccentMinLightness - kQuantum));
      expect(lightOf(accent), lessThan(kAccentMaxLightness + kQuantum));
    });

    test('pulls a washed-out cover colour back down into the band', () {
      final accent = normalizeAccent(const Color(0xFFFDF2F4));
      expect(lightOf(accent), lessThan(kAccentMaxLightness + kQuantum));
    });

    test('gives a chromatic colour a saturation floor', () {
      final accent = normalizeAccent(const Color(0xFF4C5A7A));
      expect(
          satOf(accent), greaterThanOrEqualTo(kAccentSaturationFloor - 0.01));
    });

    test('leaves a neutral neutral', () {
      final accent = normalizeAccent(const Color(0xFF777777));
      expect(satOf(accent), lessThan(kMinChroma));
    });
  });

  group('ExtractedPalette serialization', () {
    test('round-trips the accent and the neutral flag', () {
      final palette = ExtractedPalette.create(swatches: const [
        Swatch(color: Color(0xFFDADADB), population: 7273),
        Swatch(color: Color(0xFF5E5AF4), population: 1414),
      ]);

      final restored = ExtractedPalette.fromJson(palette.toJson());

      expect(restored.accent, palette.accent);
      expect(restored.isNeutral, palette.isNeutral);
      expect(restored.palette, palette.palette);
      expect(restored, palette);
    });

    test('a neutral palette survives the round trip', () {
      final palette = ExtractedPalette.create(swatches: const [
        Swatch(color: Color(0xFF9A9A9A), population: 100),
      ]);

      expect(palette.isNeutral, isTrue);
      expect(ExtractedPalette.fromJson(palette.toJson()).isNeutral, isTrue);
    });
  });

  group('end-to-end extraction', () {
    late TestEnvironment testEnv;

    setUpAll(() {
      testEnv = TestEnvironment();
      testEnv.setUp();
    });

    tearDownAll(() {
      testEnv.tearDown();
    });

    /// A cover shaped like the one that started this: a large light-grey field
    /// with a smaller block of saturated blue.
    Future<File> writeCover(String name) async {
      final image = img.Image(width: 200, height: 200);
      img.fill(image, color: img.ColorRgb8(0xDA, 0xDA, 0xDB));
      img.fillRect(image,
          x1: 40,
          y1: 60,
          x2: 160,
          y2: 130,
          color: img.ColorRgb8(0x5E, 0x5A, 0xF4));

      final file = File(p.join(testEnv.tempPath, name));
      await file.writeAsBytes(img.encodePng(image));
      return file;
    }

    test('extracts the cover\'s blue, not its grey', () async {
      final cover = await writeCover('white_and_blue.png');
      final palette = await ColorExtractionService.extractPalette(cover.path);

      expect(palette, isNotNull);
      expect(palette!.isNeutral, isFalse);
      expect(hueDelta(hueOf(palette.accent), 241.6), lessThan(20));
      expect(
          lightOf(palette.accent), greaterThan(kAccentMinLightness - kQuantum));
      expect(lightOf(palette.accent), lessThan(kAccentMaxLightness + kQuantum));
    });

    test('identical covers extract to identical palettes', () async {
      // Different paths, so neither result comes from the cache. An unseeded
      // k-means would drift between the two.
      final first = await writeCover('determinism_a.png');
      final second = await writeCover('determinism_b.png');

      final a = await ColorExtractionService.extractPalette(first.path);
      final b = await ColorExtractionService.extractPalette(second.path);

      expect(a, isNotNull);
      expect(a, b);
    });

    test('re-extracts when the cover file behind the path changes', () async {
      final cover = await writeCover('replaced.png');
      final before = await ColorExtractionService.extractPalette(cover.path);

      final replacement = img.Image(width: 200, height: 200);
      img.fill(replacement, color: img.ColorRgb8(0x0E, 0x9F, 0x4C));
      await cover.writeAsBytes(img.encodePng(replacement));
      await cover.setLastModified(
        DateTime.now().add(const Duration(seconds: 5)),
      );

      final after = await ColorExtractionService.extractPalette(cover.path);

      expect(after, isNotNull);
      expect(after, isNot(before));
      expect(hueDelta(hueOf(after!.accent), hueOf(const Color(0xFF0E9F4C))),
          lessThan(20));
    });
  });
}

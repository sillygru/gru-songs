import 'dart:math';

import 'package:flutter/material.dart';

/// One quantised region of a cover, as produced by clustering.
class Swatch {
  final Color color;
  final int population;

  const Swatch({required this.color, required this.population});

  @override
  bool operator ==(Object other) =>
      other is Swatch && other.color == color && other.population == population;

  @override
  int get hashCode => Object.hash(color, population);
}

/// The accent chosen for a cover, plus the swatches it was chosen from.
///
/// [accent] is already corrected for legibility against the app's near-black
/// surface — nothing downstream should lighten, saturate or blend it again.
/// That single-correction rule is what keeps the player and the rest of the app
/// on the same colour.
class CoverAccent {
  final Color accent;

  /// Ranked by population, uncorrected. Backdrops and scrims want the colours
  /// as they actually appear on the artwork, not the accent-corrected form.
  final List<Color> swatches;

  /// The cover carries no usable chroma (true black-and-white artwork). The
  /// theme renders its OLED variant in that case rather than inventing a hue.
  final bool isNeutral;

  const CoverAccent({
    required this.accent,
    required this.swatches,
    required this.isNeutral,
  });
}

/// Below this much [_chroma] a swatch is effectively grey. Its hue is JPEG
/// noise or a paper-white cast, and treating it as a real colour is how a
/// white-and-blue cover ends up salmon. Roughly 20/255 of channel spread.
const double kMinChroma = 0.08;

/// Accents keep at least this much saturation so they read as a colour rather
/// than a tint. Only applied to swatches that are *already* chromatic — never
/// used to drag a neutral over [kMinChroma].
const double kAccentSaturationFloor = 0.28;

/// Legible band against the near-black surface: dark enough to sit under white
/// text, light enough to show its hue.
const double kAccentMinLightness = 0.62;
const double kAccentMaxLightness = 0.78;

/// What a neutral cover gets. A light grey, so the OLED theme's white seed and
/// this agree.
const Color kNeutralAccent = Color(0xFFE0E0E0);

/// How much colour is actually present, as the spread between the strongest and
/// weakest channel.
///
/// Deliberately *not* HSL saturation: `#FCF8F5` is seven units of red away from
/// white and reports a saturation of 0.54, and `#03040A` reports 0.54 too. Both
/// are, to the eye, white and black. Absolute spread says 0.03 for each, which
/// is the truth, and it needs no special-casing at the ends of the lightness
/// range.
double _chroma(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  final maxChannel = max(r, max(g, b));
  final minChannel = min(r, min(g, b));
  return (maxChannel - minChannel) / 255;
}

/// Picks the cover's accent: the most *colourful* significant region, not the
/// largest one and not a blend of everything.
///
/// Averaging swatches mixes distinct hues into mud, and ranking by population
/// alone hands a white-and-blue cover its paper background. Scoring chroma
/// against `sqrt(population)` lets a small, genuinely coloured area outrank a
/// large neutral one while still ignoring stray specks.
CoverAccent selectAccent(List<Swatch> swatches) {
  if (swatches.isEmpty) {
    return const CoverAccent(
      accent: kNeutralAccent,
      swatches: [],
      isNeutral: true,
    );
  }

  final ranked = [...swatches]
    ..sort((a, b) => b.population.compareTo(a.population));
  final ordered = ranked.map((s) => s.color).toList();

  final total = swatches.fold<int>(0, (sum, s) => sum + s.population);
  if (total <= 0) {
    return CoverAccent(
      accent: kNeutralAccent,
      swatches: ordered,
      isNeutral: true,
    );
  }

  Swatch? best;
  double bestScore = 0;
  double bestChroma = 0;

  for (final swatch in swatches) {
    final chroma = _chroma(swatch.color);
    if (chroma < kMinChroma) continue;

    final score = chroma * sqrt(swatch.population / total);
    if (best == null || score > bestScore) {
      best = swatch;
      bestScore = score;
      bestChroma = chroma;
    }
  }

  if (best == null || bestChroma < kMinChroma) {
    return CoverAccent(
      accent: kNeutralAccent,
      swatches: ordered,
      isNeutral: true,
    );
  }

  return CoverAccent(
    accent: normalizeAccent(best.color),
    swatches: ordered,
    isNeutral: false,
  );
}

/// Lifts a swatch into the band where it stays legible on the app's near-black
/// surface, preserving its hue.
///
/// The saturation floor applies only to colours that already cleared
/// [kMinChroma]; a neutral passed in here stays neutral rather than having a
/// hue invented for it.
Color normalizeAccent(Color color) {
  final hsl = HSLColor.fromColor(color);
  final saturation = _chroma(color) >= kMinChroma
      ? max(hsl.saturation, kAccentSaturationFloor)
      : hsl.saturation;
  final lightness =
      hsl.lightness.clamp(kAccentMinLightness, kAccentMaxLightness);
  return hsl
      .withSaturation(saturation.clamp(0.0, 1.0))
      .withLightness(lightness)
      .toColor();
}

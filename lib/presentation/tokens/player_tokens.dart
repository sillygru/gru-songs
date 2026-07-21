import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';

/// Shared design tokens for the unified player screen.
///
/// Every pane (Lyrics / Player / Queue) imports this and hardcodes nothing.
/// The three panes read as one app because they draw from one set of values —
/// if a pane starts inventing its own spacing, radii or type, they drift apart
/// again, which is exactly what this file exists to prevent.
class PlayerTokens {
  const PlayerTokens._();

  // Spacing scale
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;

  // Corner radii
  static const double rSm = 12;
  static const double rMd = 18;
  static const double rLg = 26;
  static const double rPill = 999;

  static BorderRadius get brSm => BorderRadius.circular(rSm);
  static BorderRadius get brMd => BorderRadius.circular(rMd);
  static BorderRadius get brLg => BorderRadius.circular(rLg);
  static BorderRadius get brPill => BorderRadius.circular(rPill);

  // Motion — matches the transition timings already used by PlayerPageRoute
  static const Duration dFast = Duration(milliseconds: 180);
  static const Duration dBase = Duration(milliseconds: 260);
  static const Duration dSlow = Duration(milliseconds: 420);
  static const Curve cStandard = Curves.easeOutCubic;
  static const Curve cEmphasized = Curves.easeOutQuart;

  // Glass recipe — one blur, one fill, one border, used by every raised surface
  static const double glassBlur = 22;
  static const double glassFillAlpha = 0.18;
  static const double glassBorderAlpha = 0.10;
  static const double glassFillAlphaStrong = 0.30;

  // Shared opacity ladder for foreground text and icons
  static const double aPrimary = 1.0;
  static const double aSecondary = 0.66;
  static const double aTertiary = 0.42;
  static const double aPlayed = 0.42;

  // Layout
  static const double coverMaxFraction = 0.72;
  static const double rowHeight = 68;
  static const double artSize = 48;

  /// The accent colour for the whole screen: the palette extracted from the
  /// current cover, falling back to the theme primary.
  ///
  /// [AudioPlayerManager] already pushes extracted palettes into [themeProvider]
  /// as tracks change, so this stays in sync on its own.
  static Color accentOf(BuildContext context, WidgetRef ref) {
    final extracted = ref.watch(themeProvider).extractedColor;
    return vibrant(extracted ?? Theme.of(context).colorScheme.primary);
  }

  /// Non-watching variant for callbacks and one-shot reads.
  static Color readAccent(BuildContext context, WidgetRef ref) {
    return vibrant(
      ref.read(themeProvider).extractedColor ??
          Theme.of(context).colorScheme.primary,
    );
  }

  /// Cover palettes are frequently near-black or washed out, which leaves
  /// filled controls unreadable against the dark backdrop. This lifts them into
  /// a band that stays legible without losing the cover's hue.
  static Color vibrant(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness < 0.58
        ? 0.64
        : (hsl.lightness > 0.82 ? 0.82 : hsl.lightness);
    final saturation = hsl.saturation < 0.22 ? 0.22 : hsl.saturation;
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  /// Foreground that reads on top of [background] — used for the icon inside
  /// the filled play button, where a fixed black would vanish on dark accents.
  static Color onAccent(Color background) {
    return background.computeLuminance() > 0.45
        ? const Color(0xFF0B0B0B)
        : Colors.white;
  }

  // Type ramp — derived from the app text theme so the house style
  // (w900 headings, negative letter spacing) carries into the player.
  static TextStyle paneTitle(BuildContext context) =>
      (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w900,
        fontSize: 20,
        letterSpacing: -0.6,
        color: Colors.white,
      );

  static TextStyle trackTitle(BuildContext context) => const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        letterSpacing: -0.4,
        color: Colors.white,
      );

  static TextStyle trackSubtitle(BuildContext context) => TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        letterSpacing: -0.1,
        color: Colors.white.withValues(alpha: aSecondary),
      );

  static TextStyle meta(BuildContext context) => TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        letterSpacing: 0.1,
        color: Colors.white.withValues(alpha: aTertiary),
      );

  static TextStyle sectionLabel(BuildContext context) => TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.2,
        color: Colors.white.withValues(alpha: aTertiary),
      );

  /// Hero tag shared with [NowPlayingBar] so the cover flies between the
  /// mini bar and the player pane. Both sides must produce the same string.
  static String coverHeroTag(String songId) => 'now_playing_art_$songId';
}

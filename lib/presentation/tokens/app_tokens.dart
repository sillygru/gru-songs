import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_tokens.dart';

/// Design tokens for everything *outside* the unified player.
///
/// The player already runs on [PlayerTokens]; this file deliberately aliases
/// those values rather than re-declaring them, so the two halves of the app
/// cannot drift apart. If a number needs to change, it changes in one place.
///
/// Where the player earns its depth from blurred glass over cover art, the app
/// has no cover backdrop — so depth here comes from a flat tonal ladder
/// instead: a raised surface is a slightly lighter fill, never an outline and
/// never a shadow.
class AppTokens {
  const AppTokens._();

  // ---------------------------------------------------------------- spacing
  static const double s1 = PlayerTokens.s1; // 4
  static const double s2 = PlayerTokens.s2; // 8
  static const double s3 = PlayerTokens.s3; // 12
  static const double s4 = PlayerTokens.s4; // 16
  static const double s5 = PlayerTokens.s5; // 24
  static const double s6 = PlayerTokens.s6; // 32

  // ----------------------------------------------------------------- radii
  // Four radii, and only four. Anything else reads as a different system.
  static const double rSm = PlayerTokens.rSm; // 12
  static const double rMd = PlayerTokens.rMd; // 18
  static const double rLg = PlayerTokens.rLg; // 26
  static const double rPill = PlayerTokens.rPill;

  static BorderRadius get brSm => PlayerTokens.brSm;
  static BorderRadius get brMd => PlayerTokens.brMd;
  static BorderRadius get brLg => PlayerTokens.brLg;
  static BorderRadius get brPill => PlayerTokens.brPill;

  // ---------------------------------------------------------------- motion
  static const Duration dFast = PlayerTokens.dFast; // 180ms
  static const Duration dBase = PlayerTokens.dBase; // 260ms
  static const Duration dSlow = PlayerTokens.dSlow; // 420ms
  static const Curve cStandard = PlayerTokens.cStandard;
  static const Curve cEmphasized = PlayerTokens.cEmphasized;

  // ----------------------------------------------------------------- springs
  // The one thing the app was missing next to the player: a shared physical
  // feel for touch. A spring is defined by mass/stiffness/damping and, unlike a
  // curve, it is *interruptible* — re-run it from the element's current value
  // and velocity and it retargets smoothly instead of snapping back to 0. That
  // is the "hold your finger mid-animation" feel; every [Pressable] uses these.

  /// Standard press response — quick, barely any overshoot. Buttons, rows,
  /// nav items: the surface dips under the finger and settles back crisply.
  static const SpringDescription springSnappy = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 30,
  );

  /// A touch looser, with a hint of overshoot — for larger moving surfaces
  /// (cards, sheets) where a little bounce reads as physical rather than nervous.
  static const SpringDescription springGentle = SpringDescription(
    mass: 1,
    stiffness: 340,
    damping: 24,
  );

  /// Pronounced overshoot, for a deliberate "pop" (toggles, confirmations).
  static const SpringDescription springBouncy = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 16,
  );

  /// How far a [Pressable] scales down while held. Small on purpose — iOS press
  /// feedback is felt more than seen.
  static const double pressScale = 0.96;

  // --------------------------------------------------------- tonal surfaces
  /// Resting raised surface — grouped row blocks, cards, tiles.
  static const double surface1Alpha = 0.04;

  /// Pressed, hovered or selected. One step, not a ramp of five.
  static const double surface2Alpha = 0.08;

  /// The active/now-playing row. Accent-tinted wash, never a border.
  static const double accentWashAlpha = 0.12;

  /// Fill for a raised surface at [level] (1 or 2).
  static Color surface(int level) => Colors.white
      .withValues(alpha: level >= 2 ? surface2Alpha : surface1Alpha);

  /// Style for a secondary button — the neutral tonal fill that replaces every
  /// [OutlinedButton] in the app. A filled surface, never an outline; the
  /// primary action stays the accent-filled [FilledButton] beside it.
  static ButtonStyle get tonalButton => FilledButton.styleFrom(
        backgroundColor: surface(2),
        foregroundColor: fgPrimary,
      );

  // ------------------------------------------------------- foreground ladder
  static const double aPrimary = PlayerTokens.aPrimary; // 1.0
  static const double aSecondary = PlayerTokens.aSecondary; // 0.66
  static const double aTertiary = PlayerTokens.aTertiary; // 0.42

  static Color fg([double alpha = aPrimary]) =>
      Colors.white.withValues(alpha: alpha);

  // Const equivalents of the three rungs, for `const` widget trees where a
  // method call is not allowed.
  static const Color fgPrimary = Color(0xFFFFFFFF);
  static const Color fgSecondary = Color(0xA8FFFFFF); // 0.66
  static const Color fgTertiary = Color(0x6BFFFFFF); // 0.42

  // ------------------------------------------------------------- semantics
  // Named roles instead of Colors.red / Colors.orange / Colors.green literals,
  // pitched to sit on a dark background without shouting.
  static const Color danger = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFFB454);
  static const Color success = Color(0xFF5BD6A0);
  static const Color info = Color(0xFF6FB4FF);

  // ----------------------------------------------------------------- accent
  /// The app-wide accent: the palette extracted from the current cover,
  /// vibrance-corrected so it stays legible, falling back to the theme primary.
  ///
  /// This is the same value the player uses, which is what makes the app and
  /// the player read as one product. [AudioPlayerManager] already pushes
  /// extracted palettes into `themeProvider`, so this stays in sync on its own.
  static Color accentOf(BuildContext context, WidgetRef ref) =>
      PlayerTokens.accentOf(context, ref);

  /// Non-watching variant for callbacks and one-shot reads.
  static Color readAccent(BuildContext context, WidgetRef ref) =>
      PlayerTokens.readAccent(context, ref);

  /// Foreground that reads on top of [background] — for filled accent chips
  /// and buttons, where a fixed black would vanish on a dark accent.
  static Color onAccent(Color background) => PlayerTokens.onAccent(background);

  // -------------------------------------------------------------- type ramp
  /// Large screen title — the app's loudest text, used once per screen.
  static TextStyle screenTitle(BuildContext context) => const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 26,
        letterSpacing: -0.9,
        color: Colors.white,
      );

  /// Title inside a sheet, dialog or pushed sub-screen.
  static TextStyle paneTitle(BuildContext context) =>
      PlayerTokens.paneTitle(context);

  /// Small-caps group label above a block of rows.
  static TextStyle sectionLabel(BuildContext context) =>
      PlayerTokens.sectionLabel(context);

  /// Primary line of a list row.
  static TextStyle rowTitle(BuildContext context) =>
      PlayerTokens.trackTitle(context);

  /// Secondary line of a list row.
  static TextStyle rowSubtitle(BuildContext context) =>
      PlayerTokens.trackSubtitle(context);

  /// Counts, durations, timestamps — the quietest text in the system.
  static TextStyle meta(BuildContext context) => PlayerTokens.meta(context);

  /// The number in a stat tile.
  static TextStyle stat(BuildContext context) => const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 22,
        letterSpacing: -0.8,
        color: Colors.white,
      );

  /// Title under a media card in a carousel or grid.
  static TextStyle cardTitle(BuildContext context) => const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 15,
        letterSpacing: -0.4,
        color: Colors.white,
      );

  // ---------------------------------------------------------------- layout
  static const double rowHeight = PlayerTokens.rowHeight; // 68
  static const double artSize = PlayerTokens.artSize; // 48

  /// Bottom padding for scroll views so content clears the now-playing bar
  /// and the bottom dock.
  static const double scrollBottomInset = 120;
}

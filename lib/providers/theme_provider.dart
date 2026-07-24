import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/color_extraction_service.dart';

/// The theme has exactly one input: the palette extracted from the current
/// cover. There are no modes to persist — the artwork is the theme (see
/// [AppTheme]). This state just carries the live palette and the song it
/// belongs to.
class ThemeState {
  final ExtractedPalette? extractedPalette;

  /// The song [extractedPalette] belongs to. Extraction is asynchronous, so
  /// results can land after the user has skipped on; this is what lets a stale
  /// one be discarded instead of tinting the app with a previous track's cover.
  final String? paletteFilename;

  ThemeState({
    this.extractedPalette,
    this.paletteFilename,
  });

  Color? get extractedColor => extractedPalette?.color;

  /// The cover has no usable chroma, so the theme uses its OLED variant rather
  /// than inventing a hue.
  bool get isNeutralCover => extractedPalette?.isNeutral ?? false;

  List<Color> get palette => extractedPalette?.palette ?? [];

  ThemeState withPalette(ExtractedPalette? palette, String? filename) {
    return ThemeState(
      extractedPalette: palette,
      paletteFilename: filename,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() => ThemeState();

  /// Applies the palette extracted for [forFilename].
  ///
  /// A null [palette] clears the accent rather than leaving the previous song's
  /// colour in place — a cover that fails to decode should fall back to the
  /// default theme, not borrow another album's hue.
  void updateExtractedPalette(
    ExtractedPalette? palette, {
    required String forFilename,
  }) {
    if (state.extractedPalette == palette &&
        state.paletteFilename == forFilename) {
      return;
    }
    state = state.withPalette(palette, forFilename);
  }

  void updateExtractedColor(Color? color) {
    if (state.extractedColor != color) {
      final palette = color != null ? ExtractedPalette.single(color) : null;
      state = state.withPalette(palette, state.paletteFilename);
    }
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

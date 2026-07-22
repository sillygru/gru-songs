import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/color_extraction_service.dart';

class ThemeState {
  final AppThemeMode mode;
  final bool useCoverColor;
  final bool applyCoverColorToAll;
  final ExtractedPalette? extractedPalette;

  /// The song [extractedPalette] belongs to. Extraction is asynchronous, so
  /// results can land after the user has skipped on; this is what lets a stale
  /// one be discarded instead of tinting the app with a previous track's cover.
  final String? paletteFilename;

  ThemeState({
    required this.mode,
    this.useCoverColor = false,
    this.applyCoverColorToAll = false,
    this.extractedPalette,
    this.paletteFilename,
  });

  Color? get extractedColor => extractedPalette?.color;

  /// The cover has no usable chroma, so the theme uses its OLED variant rather
  /// than inventing a hue.
  bool get isNeutralCover => extractedPalette?.isNeutral ?? false;

  List<Color> get palette => extractedPalette?.palette ?? [];

  ThemeState copyWith({
    AppThemeMode? mode,
    bool? useCoverColor,
    bool? applyCoverColorToAll,
    ExtractedPalette? extractedPalette,
    String? paletteFilename,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      useCoverColor: useCoverColor ?? this.useCoverColor,
      applyCoverColorToAll: applyCoverColorToAll ?? this.applyCoverColorToAll,
      extractedPalette: extractedPalette ?? this.extractedPalette,
      paletteFilename: paletteFilename ?? this.paletteFilename,
    );
  }

  /// `copyWith` cannot express "clear the palette", since a null argument means
  /// "keep the current value" there.
  ThemeState withPalette(ExtractedPalette? palette, String? filename) {
    return ThemeState(
      mode: mode,
      useCoverColor: useCoverColor,
      applyCoverColorToAll: applyCoverColorToAll,
      extractedPalette: palette,
      paletteFilename: filename,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    _loadSettings();
    return ThemeState(mode: AppThemeMode.matchCover);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');
    final useCover = prefs.getBool('use_cover_color') ?? false;
    final applyAll = prefs.getBool('apply_cover_color_to_all') ?? false;

    AppThemeMode mode = AppThemeMode.matchCover;
    if (themeName != null) {
      try {
        mode = AppThemeMode.values.firstWhere(
          (e) => e.toString() == themeName,
        );
      } catch (_) {
        mode = AppThemeMode.matchCover;
        await prefs.setString('theme_mode', mode.toString());
      }
    }

    state = ThemeState(
      mode: mode,
      useCoverColor: useCover,
      applyCoverColorToAll: applyAll,
    );
  }

  Future<void> setTheme(AppThemeMode mode) async {
    final bool useCover = mode == AppThemeMode.matchCover;
    final bool applyAll = mode == AppThemeMode.matchCover;

    state = state.copyWith(
      mode: mode,
      useCoverColor: useCover,
      applyCoverColorToAll: applyAll,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());
    await prefs.setBool('use_cover_color', useCover);
    await prefs.setBool('apply_cover_color_to_all', applyAll);
  }

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

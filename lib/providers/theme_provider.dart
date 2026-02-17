import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/telemetry_service.dart';
import '../services/color_extraction_service.dart';

class ThemeState {
  final AppThemeMode mode;
  final bool useCoverColor;
  final bool applyCoverColorToAll;
  final ExtractedPalette? extractedPalette;

  ThemeState({
    required this.mode,
    this.useCoverColor = false,
    this.applyCoverColorToAll = false,
    this.extractedPalette,
  });

  Color? get extractedColor => extractedPalette?.color;

  List<Color> get palette => extractedPalette?.palette ?? [];

  ThemeState copyWith({
    AppThemeMode? mode,
    bool? useCoverColor,
    bool? applyCoverColorToAll,
    ExtractedPalette? extractedPalette,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      useCoverColor: useCoverColor ?? this.useCoverColor,
      applyCoverColorToAll: applyCoverColorToAll ?? this.applyCoverColorToAll,
      extractedPalette: extractedPalette ?? this.extractedPalette,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    _loadSettings();
    return ThemeState(mode: AppThemeMode.defaultTheme);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');
    final useCover = prefs.getBool('use_cover_color') ?? false;
    final applyAll = prefs.getBool('apply_cover_color_to_all') ?? false;

    AppThemeMode mode = AppThemeMode.defaultTheme;
    if (themeName != null) {
      try {
        mode = AppThemeMode.values.firstWhere(
          (e) => e.toString() == themeName,
        );
      } catch (_) {
        // Reset to default if theme no longer exists (e.g., ocean, sunset)
        mode = AppThemeMode.defaultTheme;
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

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'theme_mode',
          'value': mode.toString(),
        },
        requiredLevel: 2);
  }

  void updateExtractedPalette(ExtractedPalette? palette) {
    if (state.extractedPalette != palette) {
      state = state.copyWith(extractedPalette: palette);
    }
  }

  void updateExtractedColor(Color? color) {
    if (state.extractedColor != color) {
      final palette = color != null ? ExtractedPalette.single(color) : null;
      state = state.copyWith(extractedPalette: palette);
    }
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

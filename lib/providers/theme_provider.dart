import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/telemetry_service.dart';

class ThemeState {
  final AppThemeMode mode;
  final bool useCoverColor;
  final bool applyCoverColorToAll;
  final Color? extractedColor;

  ThemeState({
    required this.mode,
    this.useCoverColor = false,
    this.applyCoverColorToAll = false,
    this.extractedColor,
  });

  ThemeState copyWith({
    AppThemeMode? mode,
    bool? useCoverColor,
    bool? applyCoverColorToAll,
    Color? extractedColor,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      useCoverColor: useCoverColor ?? this.useCoverColor,
      applyCoverColorToAll: applyCoverColorToAll ?? this.applyCoverColorToAll,
      extractedColor: extractedColor ?? this.extractedColor,
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

  void updateExtractedColor(Color? color) {
    if (state.extractedColor != color) {
      state = state.copyWith(extractedColor: color);
    }
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

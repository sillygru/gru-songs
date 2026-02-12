import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/telemetry_service.dart';

class ThemeState {
  final AppThemeMode mode;
  final int customPrimaryColor;
  final int customBackgroundColor;
  final bool useCoverColor;
  final bool applyCoverColorToAll;
  final Color? extractedColor;

  ThemeState({
    required this.mode,
    this.customPrimaryColor = 0xFFE53935,
    this.customBackgroundColor = 0xFF121212,
    this.useCoverColor = false,
    this.applyCoverColorToAll = false,
    this.extractedColor,
  });

  ThemeState copyWith({
    AppThemeMode? mode,
    int? customPrimaryColor,
    int? customBackgroundColor,
    bool? useCoverColor,
    bool? applyCoverColorToAll,
    Color? extractedColor,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      customPrimaryColor: customPrimaryColor ?? this.customPrimaryColor,
      customBackgroundColor:
          customBackgroundColor ?? this.customBackgroundColor,
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
    return ThemeState(mode: AppThemeMode.classic);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');
    final customPrimary = prefs.getInt('custom_primary_color') ?? 0xFFE53935;
    final customBg = prefs.getInt('custom_background_color') ?? 0xFF121212;
    final useCover = prefs.getBool('use_cover_color') ?? false;
    final applyAll = prefs.getBool('apply_cover_color_to_all') ?? false;

    AppThemeMode mode = AppThemeMode.classic;
    if (themeName != null) {
      mode = AppThemeMode.values.firstWhere(
        (e) => e.toString() == themeName,
        orElse: () => AppThemeMode.classic,
      );
    }

    state = ThemeState(
      mode: mode,
      customPrimaryColor: customPrimary,
      customBackgroundColor: customBg,
      useCoverColor: useCover,
      applyCoverColorToAll: applyAll,
    );
  }

  Future<void> setTheme(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'theme_mode',
          'value': mode.toString(),
        },
        requiredLevel: 2);
  }

  Future<void> setCustomColors({int? primary, int? background}) async {
    state = state.copyWith(
      customPrimaryColor: primary,
      customBackgroundColor: background,
    );
    final prefs = await SharedPreferences.getInstance();
    if (primary != null) await prefs.setInt('custom_primary_color', primary);
    if (background != null) {
      await prefs.setInt('custom_background_color', background);
    }
  }

  Future<void> setCoverColorSettings({bool? useCover, bool? applyAll}) async {
    state = state.copyWith(
      useCoverColor: useCover,
      applyCoverColorToAll: applyAll,
    );

    final prefs = await SharedPreferences.getInstance();

    if (useCover != null) await prefs.setBool('use_cover_color', useCover);

    if (applyAll != null) {
      await prefs.setBool('apply_cover_color_to_all', applyAll);
    }
  }

  void updateExtractedColor(Color? color) {
    if (state.extractedColor != color) {
      state = state.copyWith(extractedColor: color);
    }
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

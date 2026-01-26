import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/telemetry_service.dart';

class ThemeState {
  final GruThemeMode mode;

  ThemeState({required this.mode});

  ThemeState copyWith({GruThemeMode? mode}) {
    return ThemeState(
      mode: mode ?? this.mode,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    _loadSettings();
    return ThemeState(mode: GruThemeMode.classic);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');

    GruThemeMode mode = GruThemeMode.classic;
    if (themeName != null) {
      mode = GruThemeMode.values.firstWhere(
        (e) => e.toString() == themeName,
        orElse: () => GruThemeMode.classic,
      );
    }

    state = ThemeState(mode: mode);
  }

  Future<void> setTheme(GruThemeMode mode) async {
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
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

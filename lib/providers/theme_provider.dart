import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/telemetry_service.dart';

class ThemeState {
  final AppThemeMode mode;

  ThemeState({required this.mode});

  ThemeState copyWith({AppThemeMode? mode}) {
    return ThemeState(
      mode: mode ?? this.mode,
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

    AppThemeMode mode = AppThemeMode.classic;
    if (themeName != null) {
      mode = AppThemeMode.values.firstWhere(
        (e) => e.toString() == themeName,
        orElse: () => AppThemeMode.classic,
      );
    }

    state = ThemeState(mode: mode);
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
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

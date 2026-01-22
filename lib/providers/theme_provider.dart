import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'providers.dart';

class ThemeState {
  final GruThemeMode mode;
  final bool syncTheme;

  ThemeState({required this.mode, required this.syncTheme});

  ThemeState copyWith({GruThemeMode? mode, bool? syncTheme}) {
    return ThemeState(
      mode: mode ?? this.mode,
      syncTheme: syncTheme ?? this.syncTheme,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    _loadSettings();
    return ThemeState(mode: GruThemeMode.classic, syncTheme: false);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');
    final syncTheme = prefs.getBool('sync_theme') ?? false;

    GruThemeMode mode = GruThemeMode.classic;
    if (themeName != null) {
      mode = GruThemeMode.values.firstWhere(
        (e) => e.toString() == themeName,
        orElse: () => GruThemeMode.classic,
      );
    }

    state = ThemeState(mode: mode, syncTheme: syncTheme);
  }

  Future<void> setTheme(GruThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());

    if (state.syncTheme) {
      // Trigger background sync
      Future.microtask(() => ref.read(userDataProvider.notifier).refresh());
    }
  }

  Future<void> setSyncTheme(bool sync) async {
    state = state.copyWith(syncTheme: sync);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_theme', sync);

    // Trigger background sync to push/pull
    Future.microtask(() => ref.read(userDataProvider.notifier).refresh());
  }

  void updateFromSync(GruThemeMode mode, bool syncTheme) {
    state = ThemeState(mode: mode, syncTheme: syncTheme);
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);

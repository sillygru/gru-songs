import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

enum AppThemeMode { defaultTheme, oled, matchCover }

class AppTheme {
  static ThemeData getTheme(ThemeState state, {Color? coverColor}) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;

    if (state.mode == AppThemeMode.matchCover && effectiveCoverColor != null) {
      return _getDynamicTheme(effectiveCoverColor);
    }

    final Color? overlayColor =
        state.useCoverColor ? effectiveCoverColor : null;

    switch (state.mode) {
      case AppThemeMode.defaultTheme:
        return _defaultTheme(overlayColor);
      case AppThemeMode.oled:
        return _oledTheme(overlayColor);
      case AppThemeMode.matchCover:
        return _defaultTheme(overlayColor);
    }
  }

  static ThemeData getPlayerTheme(ThemeState state, Color? coverColor) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;
    if ((state.mode == AppThemeMode.matchCover || state.useCoverColor) &&
        effectiveCoverColor != null) {
      return _getDynamicTheme(effectiveCoverColor);
    }
    return getTheme(state, coverColor: effectiveCoverColor);
  }

  static ThemeData _getDynamicTheme(Color seedColor) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F0F0F),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F0F0F),
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData _defaultTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? const Color(0xFFBB86FC); // Modern Violet
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: const Color(0xFF121212),
      ).copyWith(
        primary: primary,
        secondary: const Color(0xFF03DAC6),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF121212),
        indicatorColor: primary.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }

  static ThemeData _oledTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? Colors.white;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: Colors.black,
      ).copyWith(primary: primary),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121212),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.black,
        modalBackgroundColor: Colors.black,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.black,
        indicatorColor: primary.withValues(alpha: 0.2),
      ),
    );
  }
}

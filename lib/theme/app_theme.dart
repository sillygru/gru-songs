import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../providers/theme_provider.dart';

enum AppThemeMode { classic, oled, ocean, sunset, custom }

class AppTheme {
  static ThemeData getTheme(ThemeState state, {Color? coverColor}) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;

    // If cover color should be used for the whole app
    if (state.useCoverColor &&
        state.applyCoverColorToAll &&
        effectiveCoverColor != null) {
      return _getDynamicTheme(effectiveCoverColor);
    }

    final Color? overlayColor =
        (state.useCoverColor && !state.applyCoverColorToAll)
            ? effectiveCoverColor
            : null;

    switch (state.mode) {
      case AppThemeMode.classic:
        return _classicTheme(overlayColor);
      case AppThemeMode.oled:
        return _oledTheme(overlayColor);
      case AppThemeMode.ocean:
        return _oceanTheme(overlayColor);
      case AppThemeMode.sunset:
        return _sunsetTheme(overlayColor);
      case AppThemeMode.custom:
        return _getCustomTheme(
          Color(state.customPrimaryColor),
          Color(state.customBackgroundColor),
          overlayColor,
        );
    }
  }

  static ThemeData getPlayerTheme(ThemeState state, Color? coverColor) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;
    if (state.useCoverColor && effectiveCoverColor != null) {
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
        surface: AppPalette.backgroundDark,
      ),
      scaffoldBackgroundColor: AppPalette.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.backgroundDark,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData _getCustomTheme(Color primary, Color background,
      [Color? overridePrimary]) {
    final effectivePrimary = overridePrimary ?? primary;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: effectivePrimary,
        brightness: Brightness.dark,
        surface: background,
      ).copyWith(
        primary: effectivePrimary,
        surface: background,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData _classicTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? AppPalette.primaryRed;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: AppPalette.backgroundDark,
      ).copyWith(primary: primary),
      scaffoldBackgroundColor: AppPalette.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.backgroundDark,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppPalette.backgroundDark,
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

  static ThemeData _oceanTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? Colors.cyanAccent;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: AppPalette.backgroundOcean,
      ).copyWith(primary: primary),
      scaffoldBackgroundColor: AppPalette.backgroundOcean,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.backgroundOcean,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surfaceOcean,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppPalette.backgroundOcean,
        indicatorColor: primary.withValues(alpha: 0.2),
      ),
    );
  }

  static ThemeData _sunsetTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? Colors.orange;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: const Color(0xFF2D1B2E),
      ).copyWith(
        primary: primary,
        primaryContainer: const Color(0xFF701B4B), // Rich Plum/Sunset Pink
        onPrimaryContainer: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF201020),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF201020),
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF402030),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF201020),
        indicatorColor: primary.withValues(alpha: 0.2),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'app_colors.dart';

enum AppThemeMode { classic, oled, ocean, sunset }

class AppTheme {
  static ThemeData getTheme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.classic:
        return _classicTheme;
      case AppThemeMode.oled:
        return _oledTheme;
      case AppThemeMode.ocean:
        return _oceanTheme;
      case AppThemeMode.sunset:
        return _sunsetTheme;
    }
  }

  static final ThemeData _classicTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.primaryRed,
      brightness: Brightness.dark,
      surface: AppPalette.backgroundDark,
    ),
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
      indicatorColor: AppPalette.primaryRed.withValues(alpha: 0.2),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );

  static final ThemeData _oledTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.white,
      brightness: Brightness.dark,
      surface: Colors.black,
    ),
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
      indicatorColor: Colors.white.withValues(alpha: 0.2),
    ),
  );

  static final ThemeData _oceanTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.cyan,
      brightness: Brightness.dark,
      surface: AppPalette.backgroundOcean,
      primary: Colors.cyanAccent,
    ),
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
      indicatorColor: Colors.cyan.withValues(alpha: 0.2),
    ),
  );

  static final ThemeData _sunsetTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: Brightness.dark,
      surface: const Color(0xFF2D1B2E),
    ).copyWith(
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
      indicatorColor: Colors.orange.withValues(alpha: 0.2),
    ),
  );
}

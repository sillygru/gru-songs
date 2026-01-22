import 'package:flutter/material.dart';
import 'app_colors.dart';

enum GruThemeMode { classic, oled, ocean, sunset }

class GruTheme {
  static ThemeData getTheme(GruThemeMode mode) {
    switch (mode) {
      case GruThemeMode.classic:
        return _classicTheme;
      case GruThemeMode.oled:
        return _oledTheme;
      case GruThemeMode.ocean:
        return _oceanTheme;
      case GruThemeMode.sunset:
        return _sunsetTheme;
    }
  }

  static final ThemeData _classicTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GruPalette.gruRed,
      brightness: Brightness.dark,
      surface: GruPalette.backgroundDark,
    ),
    scaffoldBackgroundColor: GruPalette.backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: GruPalette.backgroundDark,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: GruPalette.surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GruPalette.backgroundDark,
      indicatorColor: GruPalette.gruRed.withValues(alpha: 0.2),
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
      surface: GruPalette.backgroundOcean,
      primary: Colors.cyanAccent,
    ),
    scaffoldBackgroundColor: GruPalette.backgroundOcean,
    appBarTheme: const AppBarTheme(
      backgroundColor: GruPalette.backgroundOcean,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: GruPalette.surfaceOcean,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GruPalette.backgroundOcean,
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

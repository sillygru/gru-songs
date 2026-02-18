import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

enum AppThemeMode { matchCover, defaultTheme, oled, lightBlue }

class AppTheme {
  static const int _darkAlpha = 200;

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
      case AppThemeMode.lightBlue:
        return _lightBlueTheme(overlayColor);
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

  static Color _blendWithSurface(Color color, Color surface) {
    return Color.alphaBlend(color.withAlpha(_darkAlpha), surface);
  }

  static ThemeData _getDynamicTheme(Color seedColor) {
    final blendedSeed = _blendWithSurface(seedColor, const Color(0xFF0F0F0F));

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blendedSeed,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F0F0F),
      ).copyWith(
        surfaceContainerHighest: Color.alphaBlend(
            blendedSeed.withAlpha(20), const Color(0xFF1A1A1A)),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          fontSize: 32,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          fontSize: 28,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          fontSize: 22,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 24,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: Color.alphaBlend(
          blendedSeed.withAlpha(20),
          const Color(0xFF1A1A1A),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: blendedSeed.withAlpha(51),
        elevation: 0,
      ),
    );
  }

  static ThemeData _defaultTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? const Color(0xFFBB86FC);
    final blendedPrimary = overridePrimary != null
        ? _blendWithSurface(overridePrimary, const Color(0xFF0F0F0F))
        : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blendedPrimary ?? primary,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F0F0F),
      ).copyWith(
        primary: blendedPrimary ?? primary,
        secondary: const Color(0xFF03DAC6),
        surfaceContainerHighest: const Color(0xFF1A1A1A),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          fontSize: 32,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          fontSize: 28,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          fontSize: 22,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 24,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A1A),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: (blendedPrimary ?? primary).withAlpha(51),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
      ),
    );
  }

  static ThemeData _lightBlueTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? const Color(0xFFB5C3FF);
    final blendedPrimary = overridePrimary != null
        ? _blendWithSurface(overridePrimary, const Color(0xFF0F0F0F))
        : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blendedPrimary ?? primary,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F0F0F),
      ).copyWith(
        primary: blendedPrimary ?? primary,
        secondary: const Color(0xFF03DAC6),
        surfaceContainerHighest: const Color(0xFF1A1A1A),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          fontSize: 32,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          fontSize: 28,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          fontSize: 22,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 24,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A1A),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: (blendedPrimary ?? primary).withAlpha(51),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
      ),
    );
  }

  static ThemeData _oledTheme([Color? overridePrimary]) {
    final primary = overridePrimary ?? Colors.white;
    final blendedPrimary =
        overridePrimary != null && overridePrimary != Colors.white
            ? _blendWithSurface(overridePrimary, Colors.black)
            : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blendedPrimary ?? primary,
        brightness: Brightness.dark,
        surface: Colors.black,
      ).copyWith(
        primary: blendedPrimary ?? primary,
        surfaceContainerHighest: const Color(0xFF121212),
      ),
      scaffoldBackgroundColor: Colors.black,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          fontSize: 32,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          fontSize: 28,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          fontSize: 22,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 24,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121212),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.black,
        modalBackgroundColor: Colors.black,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: (blendedPrimary ?? primary).withAlpha(51),
        elevation: 0,
      ),
    );
  }
}

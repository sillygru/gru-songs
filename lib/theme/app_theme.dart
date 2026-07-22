import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../presentation/tokens/app_tokens.dart';

enum AppThemeMode { matchCover, defaultTheme, oled, lightBlue }

/// The app is dark-only. What varies between modes is just two values — the
/// seed colour and how black the background is — so there is one theme builder
/// and the modes are arguments to it.
///
/// Component themes are declared here in full. That is deliberate: every widget
/// theme left undeclared is a widget that gets styled at its call site instead,
/// which is how the app drifted into several visual languages in the first
/// place.
class AppTheme {
  static const int _darkAlpha = 200;

  static const Color _surfaceDark = Color(0xFF0F0F0F);
  static const Color _surfaceOled = Colors.black;
  static const Color _containerDark = Color(0xFF1A1A1A);
  static const Color _containerOled = Color(0xFF121212);

  static const Color _defaultSeed = Color(0xFFBB86FC);
  static const Color _lightBlueSeed = Color(0xFFB5C3FF);

  static ThemeData getTheme(ThemeState state, {Color? coverColor}) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;

    if (state.mode == AppThemeMode.matchCover && effectiveCoverColor != null) {
      final seed = _blendWithSurface(effectiveCoverColor, _surfaceDark);
      return _buildTheme(
        seed: seed,
        background: _surfaceDark,
        container: Color.alphaBlend(seed.withAlpha(20), _containerDark),
      );
    }

    final Color? overlayColor =
        state.useCoverColor ? effectiveCoverColor : null;

    switch (state.mode) {
      case AppThemeMode.oled:
        return _buildTheme(
          seed: _seedFor(overlayColor, Colors.white, _surfaceOled),
          background: _surfaceOled,
          container: _containerOled,
        );
      case AppThemeMode.lightBlue:
        return _buildTheme(
          seed: _seedFor(overlayColor, _lightBlueSeed, _surfaceDark),
          background: _surfaceDark,
          container: _containerDark,
        );
      case AppThemeMode.defaultTheme:
      case AppThemeMode.matchCover:
        return _buildTheme(
          seed: _seedFor(overlayColor, _defaultSeed, _surfaceDark),
          background: _surfaceDark,
          container: _containerDark,
        );
    }
  }

  static ThemeData getPlayerTheme(ThemeState state, Color? coverColor) {
    final effectiveCoverColor = coverColor ?? state.extractedColor;
    if ((state.mode == AppThemeMode.matchCover || state.useCoverColor) &&
        effectiveCoverColor != null) {
      final seed = _blendWithSurface(effectiveCoverColor, _surfaceDark);
      return _buildTheme(
        seed: seed,
        background: _surfaceDark,
        container: Color.alphaBlend(seed.withAlpha(20), _containerDark),
      );
    }
    return getTheme(state, coverColor: effectiveCoverColor);
  }

  static Color _blendWithSurface(Color color, Color surface) {
    return Color.alphaBlend(color.withAlpha(_darkAlpha), surface);
  }

  /// A cover override is blended toward the background so it never comes out
  /// as a raw, over-saturated seed. White in OLED mode is left alone.
  static Color _seedFor(Color? override, Color fallback, Color background) {
    if (override == null) return fallback;
    if (override == Colors.white) return override;
    return _blendWithSurface(override, background);
  }

  static ThemeData _buildTheme({
    required Color seed,
    required Color background,
    required Color container,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: background,
    ).copyWith(
      primary: seed,
      surfaceContainerHighest: container,
      // Backstop: any Material widget that still reaches for an outline colour
      // of its own draws nothing.
      outline: Colors.transparent,
      outlineVariant: Colors.transparent,
    );

    final onSurfaceVariant =
        Colors.white.withValues(alpha: AppTokens.aSecondary);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,

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
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.9,
          fontSize: 26,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          fontSize: 12,
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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

      // Flat tonal, never bordered, never elevated.
      cardTheme: CardThemeData(
        color: AppTokens.surface(1),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.brMd,
          side: BorderSide.none,
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMd),
        iconColor: onSurfaceVariant,
        textColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.4,
          color: Colors.white,
        ),
        subtitleTextStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          letterSpacing: -0.1,
          color: onSurfaceVariant,
        ),
        selectedColor: seed,
        tileColor: Colors.transparent,
        selectedTileColor: seed.withValues(alpha: AppTokens.accentWashAlpha),
      ),

      // Groups are separated by spacing, not by lines.
      dividerTheme: const DividerThemeData(
        color: Colors.transparent,
        space: 0,
        thickness: 0,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Color.alphaBlend(AppTokens.surface(2), background),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brLg),
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 20,
          letterSpacing: -0.6,
          color: Colors.white,
        ),
        contentTextStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          letterSpacing: -0.1,
          color: onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Color.alphaBlend(AppTokens.surface(1), background),
        modalBackgroundColor:
            Color.alphaBlend(AppTokens.surface(1), background),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rLg),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.12),
          background,
        ),
        contentTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
        actionTextColor: seed,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppTokens.s3),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMd),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: Color.alphaBlend(AppTokens.surface(2), background),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brMd),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.white,
        ),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            Color.alphaBlend(AppTokens.surface(2), background),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppTokens.brMd),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: AppTokens.onAccent(seed),
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: AppTokens.s3,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.2,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seed,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s2,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Outlined buttons would draw a border by definition; render them tonal.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppTokens.surface(2),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: AppTokens.s3,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: -0.2,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          highlightColor: Colors.white.withValues(alpha: 0.06),
          shape: const CircleBorder(),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppTokens.surface(1),
          foregroundColor: onSurfaceVariant,
          selectedBackgroundColor:
              seed.withValues(alpha: AppTokens.accentWashAlpha),
          selectedForegroundColor: seed,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
        ),
      ),

      // Filled, never outlined — this is what kills every text-field box.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surface(1),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s3,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: AppTokens.aTertiary),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppTokens.surface(1),
        selectedColor: seed.withValues(alpha: AppTokens.accentWashAlpha),
        disabledColor: AppTokens.surface(1),
        side: BorderSide.none,
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: seed,
        ),
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: seed,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
        thumbColor: seed,
        overlayColor: seed.withValues(alpha: 0.14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackShape: const RoundedRectSliderTrackShape(),
        valueIndicatorColor: seed,
        valueIndicatorTextStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppTokens.onAccent(seed),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppTokens.onAccent(seed)
              : Colors.white.withValues(alpha: AppTokens.aSecondary),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? seed
              : Colors.white.withValues(alpha: 0.10),
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll<double>(0),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? seed
              : Colors.white.withValues(alpha: 0.10),
        ),
        checkColor: WidgetStatePropertyAll(AppTokens.onAccent(seed)),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? seed
              : Colors.white.withValues(alpha: AppTokens.aTertiary),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        indicatorColor: seed,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: seed,
        unselectedLabelColor:
            Colors.white.withValues(alpha: AppTokens.aTertiary),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          letterSpacing: -0.4,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: -0.4,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: seed.withValues(alpha: AppTokens.accentWashAlpha),
        indicatorShape: RoundedRectangleBorder(borderRadius: AppTokens.brPill),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        elevation: 0,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? seed
                : Colors.white.withValues(alpha: AppTokens.aTertiary),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: states.contains(WidgetState.selected)
                ? seed
                : Colors.white.withValues(alpha: AppTokens.aTertiary),
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: seed,
        linearTrackColor: Colors.white.withValues(alpha: 0.08),
        circularTrackColor: Colors.transparent,
        linearMinHeight: 3,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Color.alphaBlend(AppTokens.surface(2), background),
          borderRadius: AppTokens.brSm,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: Colors.white,
        ),
      ),

      iconTheme: const IconThemeData(color: Colors.white, size: 24),

      splashColor: Colors.white.withValues(alpha: 0.04),
      highlightColor: Colors.white.withValues(alpha: 0.04),
    );
  }
}

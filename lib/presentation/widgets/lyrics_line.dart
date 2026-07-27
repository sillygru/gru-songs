import 'dart:ui';
import 'package:flutter/material.dart';

class LyricsLine extends StatelessWidget {
  final String text;
  final String? translatedText;
  final String? translationMode;
  final bool isActive;
  final bool isPlayed;
  final double blurSigma;
  final bool hasTime;
  final double activeFontSize;
  final double inactiveFontSize;
  final Color activeColor;
  final double glowIntensity;
  final VoidCallback? onTap;

  const LyricsLine({
    super.key,
    required this.text,
    this.translatedText,
    this.translationMode,
    required this.isActive,
    required this.isPlayed,
    required this.blurSigma,
    required this.hasTime,
    required this.activeFontSize,
    required this.inactiveFontSize,
    required this.activeColor,
    required this.glowIntensity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = inactiveFontSize;
    final baseOpacity = isPlayed ? 1.0 : 0.72;
    final resolvedBlurSigma = blurSigma < 0 ? 0.0 : blurSigma;
    final showSubtext = translationMode == 'subtext' &&
        translatedText != null &&
        translatedText!.trim().isNotEmpty;
    final isReplace = translationMode == 'replace' &&
        translatedText != null &&
        translatedText!.trim().isNotEmpty;

    final primaryText = isReplace ? translatedText! : text;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: InkWell(
          onTap: hasTime ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: resolvedBlurSigma),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            builder: (context, sigma, child) {
              if (sigma <= 0) return child!;
              return ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              );
            },
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: baseOpacity),
                height: 1.28,
                letterSpacing: -0.45,
                shadows: isActive
                    ? [
                        Shadow(
                          color: activeColor.withValues(
                              alpha: 0.14 * glowIntensity),
                          blurRadius: 10 * glowIntensity,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: FractionallySizedBox(
                widthFactor: 0.92,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        primaryText,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    if (showSubtext) ...[
                      const SizedBox(height: 4),
                      Text(
                        translatedText!,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: fontSize * 0.72,
                          fontWeight: FontWeight.w400,
                          color: isActive
                              ? activeColor.withValues(alpha: 0.90)
                              : Colors.white
                                  .withValues(alpha: isPlayed ? 0.55 : 0.38),
                          height: 1.2,
                          letterSpacing: -0.2,
                          shadows: null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

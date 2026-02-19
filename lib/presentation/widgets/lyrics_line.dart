import 'dart:ui';
import 'package:flutter/material.dart';

class LyricsLine extends StatelessWidget {
  final String text;
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
    final fontSize = activeFontSize;
    final baseOpacity = isPlayed ? 1.0 : 0.72;
    final resolvedBlurSigma = blurSigma < 0 ? 0.0 : blurSigma;

    return AnimatedContainer(
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
            return ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: child,
            );
          },
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 240),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: Colors.white.withValues(alpha: baseOpacity),
              height: 1.28,
              letterSpacing: -0.45,
              shadows: isActive
                  ? [
                      Shadow(
                        color:
                            activeColor.withValues(alpha: 0.14 * glowIntensity),
                        blurRadius: 10 * glowIntensity,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: FractionallySizedBox(
              widthFactor: 0.92,
              alignment: Alignment.centerLeft,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

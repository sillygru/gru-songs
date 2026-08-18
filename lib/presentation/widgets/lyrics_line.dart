import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/models/rich_lyrics.dart';
import '../tokens/player_tokens.dart';

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
  final Duration playbackPosition;
  final RichLyricLine? wordLine;
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
    this.playbackPosition = Duration.zero,
    this.wordLine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBlurSigma = blurSigma < 0 ? 0.0 : blurSigma;
    final translation = translatedText?.trim();
    final showSubtext = translationMode == 'subtext' &&
        translation != null &&
        translation.isNotEmpty;
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    final primaryText = isReplace ? translation : text;

    final fontSize = isActive ? activeFontSize : inactiveFontSize;
    final lineOpacity = isActive ? 1.0 : (isPlayed ? 0.58 : 0.34);

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: PlayerTokens.dFast,
        curve: PlayerTokens.cStandard,
        padding: const EdgeInsets.symmetric(
          horizontal: PlayerTokens.s5,
          vertical: PlayerTokens.s3,
        ),
        child: InkWell(
          onTap: hasTime ? onTap : null,
          borderRadius: PlayerTokens.brMd,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: resolvedBlurSigma),
            duration: PlayerTokens.dBase,
            curve: PlayerTokens.cStandard,
            builder: (context, sigma, child) {
              if (sigma <= 0) return child ?? const SizedBox.shrink();
              return ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              );
            },
            child: AnimatedScale(
              scale: isActive ? 1.0 : 0.95,
              alignment: Alignment.centerLeft,
              duration: PlayerTokens.dFast,
              curve: PlayerTokens.cStandard,
              child: AnimatedDefaultTextStyle(
                duration: PlayerTokens.dFast,
                curve: PlayerTokens.cStandard,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: lineOpacity),
                  height: 1.22,
                  letterSpacing: -0.55,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: activeColor.withValues(
                              alpha: 0.22 * glowIntensity,
                            ),
                            blurRadius: 14 * glowIntensity,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: FractionallySizedBox(
                  widthFactor: 0.94,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPrimaryText(primaryText, lineOpacity),
                      if (showSubtext) ...[
                        const SizedBox(height: PlayerTokens.s1),
                        Text(
                          translation,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: fontSize * 0.68,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? activeColor.withValues(alpha: 0.88)
                                : Colors.white.withValues(
                                    alpha: isPlayed ? 0.48 : 0.28,
                                  ),
                            height: 1.2,
                            letterSpacing: -0.2,
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
      ),
    );
  }

  Widget _buildPrimaryText(String primaryText, double lineOpacity) {
    final timedLine = wordLine;
    final translation = translatedText?.trim();
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    if (isReplace || timedLine == null || timedLine.words.isEmpty) {
      return Text(primaryText, textAlign: TextAlign.left);
    }

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < timedLine.words.length; index++)
          _TimedWord(
            word: timedLine.words[index],
            position: playbackPosition,
            activeColor: activeColor,
            baseColor: Colors.white.withValues(alpha: lineOpacity),
            appendSpace: index < timedLine.words.length - 1,
          ),
      ],
    );
  }
}

/// A small animated word overlay. Rich-sync supplies exact word times; the
/// generated fallback supplies weighted line timing and punctuation pauses.
class _TimedWord extends StatelessWidget {
  final RichLyricWord word;
  final Duration position;
  final Color activeColor;
  final Color baseColor;
  final bool appendSpace;

  const _TimedWord({
    required this.word,
    required this.position,
    required this.activeColor,
    required this.baseColor,
    required this.appendSpace,
  });

  @override
  Widget build(BuildContext context) {
    final durationMs = word.duration.inMilliseconds;
    final progress = durationMs <= 0
        ? (position >= word.start ? 1.0 : 0.0)
        : ((position - word.start).inMilliseconds / durationMs).clamp(0.0, 1.0);
    final targetColor =
        Color.lerp(baseColor, activeColor, progress) ?? baseColor;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress),
      duration: PlayerTokens.dFast,
      curve: Curves.easeOut,
      builder: (context, animatedProgress, child) {
        final color =
            Color.lerp(baseColor, activeColor, animatedProgress) ?? targetColor;
        return AnimatedDefaultTextStyle(
          duration: PlayerTokens.dFast,
          curve: PlayerTokens.cStandard,
          style: DefaultTextStyle.of(context).style.copyWith(color: color),
          child: Transform.scale(
            scale: 1.0 + animatedProgress * 0.018,
            alignment: Alignment.center,
            child: Text('${word.text}${appendSpace ? ' ' : ''}'),
          ),
        );
      },
    );
  }
}

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

    final lineOpacity = isActive ? 1.0 : (isPlayed ? 0.58 : 0.34);

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: PlayerTokens.dBase,
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
            child: AnimatedDefaultTextStyle(
              duration: PlayerTokens.dBase,
              curve: PlayerTokens.cStandard,
              style: TextStyle(
                fontSize: PlayerTokens.lyricsFontSize,
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
                          fontSize: PlayerTokens.lyricsFontSize *
                              PlayerTokens.lyricsTranslationScale,
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

    final initialPosition = playbackPosition.inMicroseconds.toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: initialPosition),
      duration: PlayerTokens.dFast,
      curve: PlayerTokens.cStandard,
      builder: (context, animatedPosition, _) {
        final position = Duration(microseconds: animatedPosition.round());
        final baseColor = Colors.white.withValues(alpha: lineOpacity);
        final defaultStyle = DefaultTextStyle.of(context).style;
        final spans = <TextSpan>[];

        for (var index = 0; index < timedLine.words.length; index++) {
          final word = timedLine.words[index];
          final progress = _wordProgress(word, position);
          final color =
              Color.lerp(baseColor, activeColor, progress) ?? baseColor;
          spans.add(
            TextSpan(
              text:
                  '${word.text}${index < timedLine.words.length - 1 ? ' ' : ''}',
              style: defaultStyle.copyWith(color: color),
            ),
          );
        }

        return RichText(
          textAlign: TextAlign.left,
          text: TextSpan(style: defaultStyle, children: spans),
        );
      },
    );
  }

  static double _wordProgress(RichLyricWord word, Duration position) {
    if (position < word.start) return 0;
    if (position >= word.end) return 1;
    final duration = word.duration.inMicroseconds;
    if (duration <= 0) return 1;
    return ((position - word.start).inMicroseconds / duration).clamp(0.0, 1.0);
  }
}

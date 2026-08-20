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
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.95,
        alignment: Alignment.centerLeft,
        duration: PlayerTokens.dLyricsLine,
        curve: PlayerTokens.cStandard,
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
                            blurRadius:
                                PlayerTokens.lyricsWordGlowBlur * glowIntensity,
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
                      _buildPrimaryText(context, primaryText, lineOpacity),
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
      ),
    );
  }

  Widget _buildPrimaryText(
    BuildContext context,
    String primaryText,
    double lineOpacity,
  ) {
    final timedLine = wordLine;
    final translation = translatedText?.trim();
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    if (isReplace || timedLine == null || timedLine.words.isEmpty) {
      return Text(primaryText, textAlign: TextAlign.left);
    }

    final position = playbackPosition;
    final baseColor = Colors.white.withValues(alpha: lineOpacity);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];

    for (var index = 0; index < timedLine.words.length; index++) {
      final word = timedLine.words[index];
      final progress = _wordProgress(word, position);
      final pulse = _wordPulse(word, position);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress),
            duration: timedLine.isSimulated
                ? PlayerTokens.dLyricsHighlightIn
                : PlayerTokens.dFast,
            curve: PlayerTokens.cStandard,
            builder: (context, animatedProgress, _) {
              final color = Color.lerp(
                    baseColor,
                    activeColor,
                    animatedProgress,
                  ) ??
                  baseColor;
              final animatedPulse = Curves.easeOut.transform(pulse);
              final wordStyle = defaultStyle.copyWith(
                color: color,
                shadows: animatedProgress > 0
                    ? [
                        Shadow(
                          color: activeColor.withValues(
                            alpha: 0.28 * animatedProgress,
                          ),
                          blurRadius: PlayerTokens.lyricsWordGlowBlur *
                              animatedProgress,
                        ),
                      ]
                    : null,
              );
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: animatedPulse),
                duration: PlayerTokens.dFast,
                curve: PlayerTokens.cStandard,
                builder: (context, pulseValue, _) => Transform.translate(
                  offset: Offset(
                    PlayerTokens.lyricsWordWobbleShiftEm *
                        (defaultStyle.fontSize ?? PlayerTokens.lyricsFontSize) *
                        pulseValue,
                    0,
                  ),
                  child: Transform.scale(
                    alignment: Alignment.center,
                    scaleX: 1 + PlayerTokens.lyricsWordWobbleScale * pulseValue,
                    child: Text(word.text, style: wordStyle),
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (index < timedLine.words.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }

    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(style: defaultStyle, children: spans),
    );
  }

  static double _wordProgress(RichLyricWord word, Duration position) {
    if (position < word.start) return 0;
    if (word.duration <= Duration.zero) return 1;

    final duration = word.duration.inMicroseconds.toDouble();
    final lead = duration * PlayerTokens.lyricsHighlightLeadRatio;
    final swipeDuration = duration * PlayerTokens.lyricsHighlightDurationRatio;
    final elapsed = position.inMicroseconds - word.start.inMicroseconds + lead;
    return (elapsed / swipeDuration).clamp(0.0, 1.0);
  }

  static double _wordPulse(RichLyricWord word, Duration position) {
    if (position < word.start) return 0;
    final elapsed = position - word.start;
    if (elapsed >= PlayerTokens.dLyricsWordWobble) return 0;
    return 1 -
        elapsed.inMicroseconds / PlayerTokens.dLyricsWordWobble.inMicroseconds;
  }
}

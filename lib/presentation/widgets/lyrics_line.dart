import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/models/rich_lyrics.dart';
import '../tokens/player_tokens.dart';

/// Renders one lyric line with large type and smooth word-level highlighting.
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
    final resolvedBlurSigma = blurSigma.clamp(0.0, 2.0);
    final translation = translatedText?.trim();
    final showSubtext = translationMode == 'subtext' &&
        translation != null &&
        translation.isNotEmpty;
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    final primaryText = isReplace ? translation : text;
    final lineOpacity = isActive ? 1.0 : (isPlayed ? 0.60 : 0.38);

    return RepaintBoundary(
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.97,
        alignment: Alignment.centerLeft,
        duration: PlayerTokens.dLyricsLine,
        curve: PlayerTokens.cStandard,
        child: AnimatedContainer(
          duration: PlayerTokens.dBase,
          curve: PlayerTokens.cStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: PlayerTokens.s4,
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
                if (sigma <= 0.05) return child ?? const SizedBox.shrink();
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
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: lineOpacity),
                  height: 1.28,
                  letterSpacing: -0.4,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: activeColor.withValues(
                              alpha: 0.30 * glowIntensity,
                            ),
                            blurRadius: 16 * glowIntensity,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: SizedBox(
                  width: double.infinity,
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
                                    alpha: isPlayed ? 0.50 : 0.30,
                                  ),
                            height: 1.22,
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

    // Tween the playhead between position-stream updates instead of restarting
    // one animation per word. This keeps the handoff fluid without changing the
    // timing model supplied by RichLyrics, including simulated word timings.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: playbackPosition.inMicroseconds.toDouble()),
      duration: PlayerTokens.dLyricsWordProgress,
      curve: Curves.linear,
      builder: (context, animatedMicros, _) {
        final position = Duration(microseconds: animatedMicros.round());
        final baseColor = Colors.white.withValues(alpha: lineOpacity);
        final highlightColor = activeColor.withValues(alpha: lineOpacity);
        final spans = <TextSpan>[];

        for (var index = 0; index < timedLine.words.length; index++) {
          final word = timedLine.words[index];
          final progress = _wordProgress(word, position);
          final pulse = _wordPulse(word, position);
          final color =
              Color.lerp(baseColor, highlightColor, progress) ?? baseColor;

          spans.add(
            TextSpan(
              text:
                  '${word.text}${index < timedLine.words.length - 1 ? ' ' : ''}',
              style: TextStyle(
                color: color,
                shadows: pulse <= 0.02
                    ? null
                    : [
                        Shadow(
                          color: activeColor.withValues(
                            alpha: 0.28 * pulse * lineOpacity,
                          ),
                          blurRadius: 12 * pulse,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
            ),
          );
        }

        return Text.rich(
          TextSpan(children: spans),
          textAlign: TextAlign.left,
        );
      },
    );
  }

  static double _wordProgress(RichLyricWord word, Duration position) {
    if (position < word.start) return 0;
    if (word.duration <= Duration.zero) return 1;

    final duration = word.duration.inMicroseconds.toDouble();
    final lead = duration * PlayerTokens.lyricsHighlightLeadRatio;
    final swipeDuration = duration * PlayerTokens.lyricsHighlightDurationRatio;
    final elapsed = position.inMicroseconds - word.start.inMicroseconds + lead;
    final revealRatio = (1 + PlayerTokens.lyricsHighlightLeadRatio) /
        PlayerTokens.lyricsHighlightDurationRatio;
    return ((elapsed / swipeDuration) / revealRatio).clamp(0.0, 1.0);
  }

  static double _wordPulse(RichLyricWord word, Duration position) {
    if (position < word.start) return 0;

    final elapsed = (position - word.start).inMicroseconds;
    final duration = word.duration.inMicroseconds;
    final pulseDuration = math.max(
      duration > 0 ? (duration * 1.2).round() : 0,
      const Duration(milliseconds: 1200).inMicroseconds,
    );
    if (elapsed >= pulseDuration) return 0;

    return Curves.easeOut.transform(
      (1 - elapsed / pulseDuration).clamp(0.0, 1.0),
    );
  }
}

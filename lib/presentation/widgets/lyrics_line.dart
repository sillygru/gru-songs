import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/models/rich_lyrics.dart';
import '../tokens/player_tokens.dart';

/// Renders an individual lyric line with BetterLyrics typography, spatial depth,
/// and exact Web Animations API / CSS Houdini-style word-by-word synchronization.
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
    final resolvedBlurSigma = blurSigma < 0 ? 0.0 : blurSigma.clamp(0.0, 2.0);
    final translation = translatedText?.trim();
    final showSubtext = translationMode == 'subtext' &&
        translation != null &&
        translation.isNotEmpty;
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    final primaryText = isReplace ? translation : text;

    // BetterLyrics contrast ladder: active 100% white, past 60%, upcoming 38%
    final lineOpacity = isActive ? 1.0 : (isPlayed ? 0.60 : 0.38);

    return RepaintBoundary(
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.96,
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
                              alpha: 0.35 * glowIntensity,
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

    final baseStyle = DefaultTextStyle.of(context).style;
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < timedLine.words.length; index++)
          _BetterLyricsWord(
            key: ValueKey('${timedLine.start.inMicroseconds}:$index'),
            word: timedLine.words[index],
            position: playbackPosition,
            activeColor: activeColor,
            baseStyle: baseStyle,
            lineOpacity: lineOpacity,
            trailingSpace: index < timedLine.words.length - 1,
          ),
      ],
    );
  }
}

/// Renders a single word implementing the exact BetterLyrics visual specifications:
///
/// 1. **Karaoke Linear Gradient Swipe** (using `ShaderMask` corresponding to BetterLyrics CSS `background-clip: text`
///    and `@property --lyric-transition-amount-start/end`).
/// 2. **Syllable Kinetic Wobble**:
///    - `0%`: scaleX(1)
///    - `12.5%`: translateX(0.05em) scaleX(1.025)
///    - `75%`: translateX(0) scaleX(1)
///    - `100%`: scaleX(1)
/// 3. **Radial Glow Pulse**:
///    - Duration = `max(wordDuration * 1.2, 1200ms)`.
///    - Long held notes (>=1500ms) receive amplified bloom.
class _BetterLyricsWord extends StatelessWidget {
  final RichLyricWord word;
  final Duration position;
  final Color activeColor;
  final TextStyle baseStyle;
  final double lineOpacity;
  final bool trailingSpace;

  const _BetterLyricsWord({
    super.key,
    required this.word,
    required this.position,
    required this.activeColor,
    required this.baseStyle,
    required this.lineOpacity,
    required this.trailingSpace,
  });

  @override
  Widget build(BuildContext context) {
    final text = '${word.text}${trailingSpace ? ' ' : ''}';
    final fontSize = baseStyle.fontSize ?? PlayerTokens.lyricsFontSize;
    final isLongWord = word.duration.inMilliseconds >= 1500;

    // BetterLyrics progress, wobble, and glow calculations
    final swipeProgress = _swipeProgress(word, position);
    final glow = _glowIntensity(word, position);
    final wobble = _wordWobble(word, position, fontSize);

    final highlightStyle = baseStyle.copyWith(
      color: activeColor.withValues(alpha: lineOpacity),
      shadows: glow <= 0.02
          ? null
          : [
              Shadow(
                color: activeColor.withValues(
                  alpha: (isLongWord ? 0.45 : 0.32) * glow,
                ),
                blurRadius: (isLongWord ? 18.0 : 12.0) * glow,
                offset: const Offset(0, 1),
              ),
            ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: swipeProgress),
      duration: const Duration(milliseconds: 50),
      curve: Curves.linear,
      builder: (context, progress, _) {
        final clampedProgress = progress.clamp(0.0, 1.0);
        final baseTextWidget = Text(text, style: baseStyle);
        final highlightTextWidget = Text(text, style: highlightStyle);

        final revealedHighlight = _buildGradientWipe(
          highlightTextWidget,
          clampedProgress,
        );

        final wordContent = Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            baseTextWidget,
            revealedHighlight,
          ],
        );

        // Apply BetterLyrics syllable kinetic wobble transform
        if (wobble.scaleX != 1.0 || wobble.translateX != 0.0) {
          return Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.translationValues(wobble.translateX, 0.0, 0.0)
              ..multiply(
                Matrix4.diagonal3Values(wobble.scaleX, 1.0, 1.0),
              ),
            child: wordContent,
          );
        }

        return wordContent;
      },
    );
  }

  /// Creates a soft linear gradient reveal corresponding to BetterLyrics CSS:
  /// `background-image: linear-gradient(90deg, activeColor start, transparent end); background-clip: text;`
  Widget _buildGradientWipe(Widget child, double progress) {
    if (progress <= 0.0) return const SizedBox.shrink();
    if (progress >= 1.0) return child;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) {
        if (bounds.width <= 0) {
          return const LinearGradient(
            colors: [Colors.white, Colors.white],
          ).createShader(bounds);
        }

        // Feather gradient width across the glyphs (~20% of word width)
        const feather = 0.20;
        final startStop = (progress - feather * 0.5).clamp(0.0, 1.0);
        final endStop = (progress + feather * 0.5).clamp(0.0, 1.0);

        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, startStop, endStop, 1.0],
          colors: const [
            Colors.white,
            Colors.white,
            Colors.transparent,
            Colors.transparent,
          ],
        ).createShader(bounds);
      },
      child: ExcludeSemantics(child: child),
    );
  }

  /// Calculates the reveal progress matching BetterLyrics timing model:
  /// - Starts early at: `wordStart - SWIPE_LEAD_RATIO * wordDuration` (lead ratio = 0.10)
  /// - Total sweep duration: `SWIPE_DURATION_RATIO * wordDuration` (duration ratio = 1.6)
  /// - Reaches 100% visible glyph illumination at `wordStart + wordDuration`.
  static double _swipeProgress(RichLyricWord word, Duration position) {
    if (position < word.start) return 0.0;
    if (word.duration <= Duration.zero) return 1.0;

    final durationUs = word.duration.inMicroseconds.toDouble();
    final leadUs = durationUs * 0.10;
    final swipeDurationUs = durationUs * 1.6;
    final elapsedUs =
        position.inMicroseconds - word.start.inMicroseconds + leadUs;

    if (swipeDurationUs <= 0) return 1.0;

    // Normalizing so that at (wordStart + wordDuration), the visible glyphs reach 100%
    const textRevealRatio = 1.1 / 1.6;
    final normalized = (elapsedUs / swipeDurationUs) / textRevealRatio;
    return normalized.clamp(0.0, 1.0);
  }

  /// Syllable kinetic wobble matching BetterLyrics keyframe curve:
  /// - `0%`: scaleX(1)
  /// - `12.5%`: translateX(0.05em) scaleX(1.025)
  /// - `75%`: translateX(0) scaleX(1)
  /// - `100%`: scaleX(1)
  /// Duration = 1.0s (or word duration for shorter words).
  static ({double scaleX, double translateX}) _wordWobble(
    RichLyricWord word,
    Duration position,
    double fontSize,
  ) {
    if (position < word.start) {
      return (scaleX: 1.0, translateX: 0.0);
    }

    final elapsedMs = (position - word.start).inMilliseconds;
    final wobbleDurationMs = word.duration > Duration.zero
        ? math.min(1000, math.max(400, word.duration.inMilliseconds))
        : 500;

    if (elapsedMs > wobbleDurationMs) {
      return (scaleX: 1.0, translateX: 0.0);
    }

    final u = (elapsedMs / wobbleDurationMs).clamp(0.0, 1.0);
    double factor;
    if (u < 0.125) {
      final p = u / 0.125;
      factor = Curves.easeOut.transform(p);
    } else if (u < 0.75) {
      final p = (u - 0.125) / 0.625;
      factor = 1.0 - Curves.easeInOut.transform(p);
    } else {
      factor = 0.0;
    }

    final scaleX = 1.0 + 0.025 * factor;
    final translateX = (fontSize * 0.05) * factor; // 0.05em in px
    return (scaleX: scaleX, translateX: translateX);
  }

  /// Radial glow pulse matching BetterLyrics:
  /// Duration = max(wordDuration * 1.2, 1200ms) with smooth ease-out decay.
  static double _glowIntensity(RichLyricWord word, Duration position) {
    if (position < word.start) return 0.0;

    final elapsedMs = (position - word.start).inMilliseconds;
    final wordDurationMs = word.duration.inMilliseconds;
    final glowDurationMs = math.max(
      (wordDurationMs * 1.2).round(),
      1200,
    );

    if (elapsedMs >= glowDurationMs) return 0.0;
    final remaining = (1.0 - elapsedMs / glowDurationMs).clamp(0.0, 1.0);
    return Curves.easeOut.transform(remaining);
  }
}

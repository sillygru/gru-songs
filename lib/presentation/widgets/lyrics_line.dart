import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/models/rich_lyrics.dart';
import '../tokens/player_tokens.dart';

/// Vocal voice alignment for lead, backing, or multi-singer lines.
enum LyricsVoiceAlignment {
  lead,
  backing,
  duet,
}

/// Renders one lyric line with dynamic scale, vocal alignment, and smooth
/// word-level karaoke highlighting and wobble physics.
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

  static LyricsVoiceAlignment detectAlignment(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return LyricsVoiceAlignment.lead;

    if (trimmed.startsWith('(Both)') ||
        trimmed.startsWith('(All)') ||
        trimmed.startsWith('[Both]') ||
        trimmed.startsWith('[All]')) {
      return LyricsVoiceAlignment.duet;
    }

    if ((trimmed.startsWith('(') && trimmed.endsWith(')')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      return LyricsVoiceAlignment.backing;
    }

    return LyricsVoiceAlignment.lead;
  }

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
    final lineOpacity = isActive
        ? PlayerTokens.lyricsActiveOpacity
        : (isPlayed
            ? PlayerTokens.lyricsPlayedOpacity
            : PlayerTokens.lyricsInactiveOpacity);

    final alignment = detectAlignment(primaryText);
    final textAlign = switch (alignment) {
      LyricsVoiceAlignment.lead => TextAlign.left,
      LyricsVoiceAlignment.backing => TextAlign.right,
      LyricsVoiceAlignment.duet => TextAlign.center,
    };
    final crossAxisAlignment = switch (alignment) {
      LyricsVoiceAlignment.lead => CrossAxisAlignment.start,
      LyricsVoiceAlignment.backing => CrossAxisAlignment.end,
      LyricsVoiceAlignment.duet => CrossAxisAlignment.center,
    };
    final scaleAlignment = switch (alignment) {
      LyricsVoiceAlignment.lead => Alignment.centerLeft,
      LyricsVoiceAlignment.backing => Alignment.centerRight,
      LyricsVoiceAlignment.duet => Alignment.center,
    };

    return RepaintBoundary(
      child: AnimatedSlide(
        offset: isActive ? const Offset(0, -0.04) : Offset.zero,
        duration: PlayerTokens.dLyricsLine,
        curve: PlayerTokens.cLyricsLine,
        child: AnimatedScale(
          scale: isActive
              ? PlayerTokens.lyricsActiveScale
              : PlayerTokens.lyricsInactiveScale,
          alignment: scaleAlignment,
          duration: PlayerTokens.dLyricsLine,
          curve: PlayerTokens.cLyricsLine,
          child: AnimatedContainer(
            duration: PlayerTokens.dLyricsLine,
            curve: PlayerTokens.cLyricsLine,
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
                  duration: PlayerTokens.dLyricsLine,
                  curve: PlayerTokens.cLyricsLine,
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
                      crossAxisAlignment: crossAxisAlignment,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPrimaryText(primaryText, lineOpacity, textAlign),
                        if (showSubtext) ...[
                          const SizedBox(height: PlayerTokens.s1),
                          Text(
                            translation,
                            textAlign: textAlign,
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
      ),
    );
  }

  Widget _buildPrimaryText(
    String primaryText,
    double lineOpacity,
    TextAlign textAlign,
  ) {
    final timedLine = wordLine;
    final translation = translatedText?.trim();
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;
    if (isReplace || timedLine == null || timedLine.words.isEmpty) {
      return Text(primaryText, textAlign: textAlign);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: playbackPosition.inMicroseconds.toDouble()),
      duration: PlayerTokens.dLyricsWordProgress,
      curve: Curves.linear,
      builder: (context, animatedMicros, _) {
        final position = Duration(microseconds: animatedMicros.round());
        final spans = <InlineSpan>[];

        for (var index = 0; index < timedLine.words.length; index++) {
          final word = timedLine.words[index];
          final wordSuffix = index < timedLine.words.length - 1 ? ' ' : '';

          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: _LyricWordWidget(
                word: word,
                position: position,
                activeColor: activeColor,
                lineOpacity: lineOpacity,
                isActive: isActive,
                wordSuffix: wordSuffix,
                textStyle: const TextStyle(
                  fontSize: PlayerTokens.lyricsFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.28,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          );
        }

        return Text.rich(
          TextSpan(children: spans),
          textAlign: textAlign,
        );
      },
    );
  }
}

class _LyricWordWidget extends StatelessWidget {
  final RichLyricWord word;
  final Duration position;
  final Color activeColor;
  final double lineOpacity;
  final bool isActive;
  final String wordSuffix;
  final TextStyle textStyle;

  const _LyricWordWidget({
    required this.word,
    required this.position,
    required this.activeColor,
    required this.lineOpacity,
    required this.isActive,
    required this.wordSuffix,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final durationUs = word.duration.inMicroseconds.toDouble();

    double progress = 0.0;
    if (durationUs > 0) {
      final elapsedUs = (position - word.start).inMicroseconds.toDouble();
      progress = (elapsedUs / durationUs).clamp(0.0, 1.0);
    } else {
      progress = position >= word.start ? 1.0 : 0.0;
    }

    final baseInactiveColor = Colors.white.withValues(
      alpha:
          lineOpacity * (isActive ? 0.35 : PlayerTokens.lyricsInactiveOpacity),
    );
    final fullActiveColor = activeColor.withValues(
      alpha: lineOpacity,
    );

    final displayText = '${word.text}$wordSuffix';

    // Base dimmed layer
    Widget child = Text(
      displayText,
      style: textStyle.copyWith(
        color: baseInactiveColor,
        shadows: null,
      ),
    );

    // Active theme-colored wipe layer with luminous leading crest
    if (isActive && progress > 0.0) {
      Widget activeText;
      if (progress >= 1.0) {
        activeText = Text(
          displayText,
          style: textStyle.copyWith(
            color: fullActiveColor,
            shadows: null,
          ),
        );
      } else {
        final s0 = (progress - 0.14).clamp(0.0, 1.0);
        final s1 = math.max(s0 + 0.001, progress.clamp(0.0, 1.0));
        final s2 = math.max(s1 + 0.001, (progress + 0.16).clamp(0.0, 1.0));
        final crestColor =
            Color.lerp(activeColor, Colors.white, 0.65) ?? Colors.white;

        activeText = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, s0, s1, s2, 1.0],
              colors: [
                activeColor,
                activeColor,
                crestColor,
                Colors.transparent,
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          child: Text(
            displayText,
            style: textStyle.copyWith(
              color: Colors.white,
              shadows: null,
            ),
          ),
        );

        final lift = -2.2 * math.sin(progress * math.pi);
        activeText = Transform.translate(
          offset: Offset(0, lift),
          child: activeText,
        );
      }

      child = Stack(
        children: [
          child,
          activeText,
        ],
      );
    }

    return child;
  }
}

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

    // Removed per-line RepaintBoundary: 40 boundaries (~1.2MB layer cache)
    // isolated blur but cost more than they saved. Single boundary around the
    // list in LyricsPane is enough; blur layers now composite directly.
    // Sigma capped at 1.4: sigma 2 at 32px text is a subtle focus cue, but
    // kernel size scales with sigma. Capping halves taps per blurring line.
    // Bypass raised to 0.6: only the two nearest off-screen lines keep blur,
    // farther ones use opacity alone — same focus cue, 3x fewer saveLayers.
    return AnimatedSlide(
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
              tween: Tween<double>(end: resolvedBlurSigma.clamp(0.0, 1.4)),
              duration: PlayerTokens.dBase,
              curve: PlayerTokens.cStandard,
              builder: (context, sigma, child) {
                if (sigma <= 0.60) return child ?? const SizedBox.shrink();
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
                      ..._buildLyricLines(primaryText, lineOpacity, textAlign),
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
    );
  }

  List<Widget> _buildLyricLines(
    String primaryText,
    double lineOpacity,
    TextAlign textAlign,
  ) {
    final isDuetTag = primaryText.trim().startsWith('(Both)') ||
        primaryText.trim().startsWith('(All)') ||
        primaryText.trim().startsWith('[Both]') ||
        primaryText.trim().startsWith('[All]');

    final timedLine = wordLine;
    final translation = translatedText?.trim();
    final isReplace = translationMode == 'replace' &&
        translation != null &&
        translation.isNotEmpty;

    if (!isReplace && timedLine != null && timedLine.words.isNotEmpty) {
      if (!isDuetTag &&
          primaryText.contains('(') &&
          primaryText.contains(')')) {
        final mainWords = <RichLyricWord>[];
        final backingWords = <RichLyricWord>[];
        var inParen = false;

        for (final word in timedLine.words) {
          final hasOpen = word.text.contains('(');
          final hasClose = word.text.contains(')');

          if (hasOpen && !hasClose) {
            inParen = true;
            backingWords.add(word);
          } else if (hasClose && inParen) {
            backingWords.add(word);
            inParen = false;
          } else if (inParen || (hasOpen && hasClose)) {
            backingWords.add(word);
          } else {
            mainWords.add(word);
          }
        }

        if (mainWords.isNotEmpty && backingWords.isNotEmpty) {
          return [
            _buildWordSpans(mainWords, lineOpacity, textAlign,
                isBacking: false),
            const SizedBox(height: PlayerTokens.s1),
            _buildWordSpans(backingWords, lineOpacity * 0.88, textAlign,
                isBacking: true),
          ];
        } else if (mainWords.isEmpty && backingWords.isNotEmpty) {
          return [
            _buildWordSpans(backingWords, lineOpacity * 0.88, textAlign,
                isBacking: true),
          ];
        }
      }

      return [
        _buildWordSpans(timedLine.words, lineOpacity, textAlign,
            isBacking: false),
      ];
    }

    // Static text path
    if (!isDuetTag && primaryText.contains('(') && primaryText.contains(')')) {
      final backingMatches = RegExp(r'\([^)]+\)').allMatches(primaryText);
      if (backingMatches.isNotEmpty) {
        final backingText = backingMatches.map((m) => m.group(0)!).join(' ');
        final mainText =
            primaryText.replaceAll(RegExp(r'\s*\([^)]+\)\s*'), ' ').trim();

        final backingStyle = TextStyle(
          fontSize: PlayerTokens.lyricsFontSize * 0.72,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: lineOpacity * 0.88),
          height: 1.25,
          letterSpacing: -0.2,
        );

        if (mainText.isNotEmpty && backingText.isNotEmpty) {
          return [
            Text(mainText, textAlign: textAlign),
            const SizedBox(height: PlayerTokens.s1),
            Text(backingText, textAlign: textAlign, style: backingStyle),
          ];
        } else if (mainText.isEmpty && backingText.isNotEmpty) {
          return [
            Text(backingText, textAlign: textAlign, style: backingStyle),
          ];
        }
      }
    }

    return [
      Text(primaryText, textAlign: textAlign),
    ];
  }

  Widget _buildWordSpans(
    List<RichLyricWord> words,
    double lineOpacity,
    TextAlign textAlign, {
    required bool isBacking,
  }) {
    final style = isBacking
        ? TextStyle(
            fontSize: PlayerTokens.lyricsFontSize * 0.72,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: -0.2,
            color: Colors.white.withValues(alpha: lineOpacity),
          )
        : TextStyle(
            fontSize: PlayerTokens.lyricsFontSize,
            fontWeight: FontWeight.w800,
            height: 1.28,
            letterSpacing: -0.4,
            color: Colors.white.withValues(alpha: lineOpacity),
          );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: playbackPosition.inMicroseconds.toDouble()),
      duration: PlayerTokens.dLyricsWordProgress,
      curve: Curves.linear,
      builder: (context, animatedMicros, _) {
        final position = Duration(microseconds: animatedMicros.round());
        final spans = <InlineSpan>[];

        for (var index = 0; index < words.length; index++) {
          final word = words[index];
          final wordSuffix = index < words.length - 1
              ? (word.text.endsWith('-') ? '' : ' ')
              : '';

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
                textStyle: style,
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

    // Active wipe: ClipRect avoids ShaderMask saveLayer per word. The
    // luminous crest is preserved as a solid active color wipe; the wobble
    // lift remains. Saves one saveLayer per animating word (~5-8 concurrent).
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
        final clipped = ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Text(
              displayText,
              style: textStyle.copyWith(
                color: fullActiveColor,
                shadows: null,
              ),
              overflow: TextOverflow.clip,
              softWrap: false,
              maxLines: 1,
            ),
          ),
        );
        final lift = -2.2 * math.sin(progress * math.pi);
        activeText = Transform.translate(
          offset: Offset(0, lift),
          child: clipped,
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

import 'dart:math' as math;
import 'package:flutter/material.dart';

class LyricsGapLoader extends StatefulWidget {
  final Duration animationDuration;

  const LyricsGapLoader({
    super.key,
    required this.animationDuration,
  });

  @override
  State<LyricsGapLoader> createState() => _LyricsGapLoaderState();
}

class _LyricsGapLoaderState extends State<LyricsGapLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Entrance takes ~1.4s regardless of gap length.
  // If gap is shorter, entrance compresses proportionally.
  static const double _entranceDurationMs = 1400.0;
  static const double _exitRatio = 0.08;
  static const double _staggerGap = 0.30;
  static const double _dotAppearDuration = 0.35;
  static const double _breathFrequencyHz = 0.42;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant LyricsGapLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationDuration != widget.animationDuration) {
      _controller
        ..duration = widget.animationDuration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final overallProgress = _controller.value;

              // Entrance normalized so dots always appear at ~1.4s rate
              final gapMs = math
                  .max(widget.animationDuration.inMilliseconds, 1)
                  .toDouble();
              final entranceEnd =
                  (_entranceDurationMs / gapMs).clamp(0.18, 1.0);
              final entranceProgress =
                  (overallProgress / entranceEnd).clamp(0.0, 1.0);

              // Exit: last _exitRatio of the gap
              final exitProgress =
                  ((overallProgress - (1.0 - _exitRatio)) / _exitRatio)
                      .clamp(0.0, 1.0);
              final exitEased = Curves.easeInCubic.transform(exitProgress);
              final exitAlpha = 1.0 - exitEased;
              final exitScale = 1.0 - exitEased * 0.2;

              return Opacity(
                opacity: exitAlpha,
                child: Transform.scale(
                  scale: exitScale,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      final staggerCenter =
                          _staggerGap * index + _dotAppearDuration * 0.5;
                      final staggerStart =
                          staggerCenter - _dotAppearDuration * 0.5;
                      final dotRaw = ((entranceProgress - staggerStart) /
                              _dotAppearDuration)
                          .clamp(0.0, 1.0);
                      final dotAppear = Curves.easeOutCubic.transform(dotRaw);

                      // Fixed-frequency breathing independent of gap length
                      final gapSeconds = gapMs / 1000.0;
                      final breathRaw = math.sin(overallProgress *
                              gapSeconds *
                              2.0 *
                              math.pi *
                              _breathFrequencyHz +
                          index * 0.35);
                      final breath =
                          Curves.easeInOutSine.transform(breathRaw * 0.5 + 0.5);

                      // Smoothly blend entrance into breathing over dotRaw 0.85-1.0
                      const blendStart = 0.85;
                      const blendEnd = 1.0;
                      final blendProgress =
                          ((dotRaw - blendStart) / (blendEnd - blendStart))
                              .clamp(0.0, 1.0);
                      final blendCurve =
                          Curves.easeInOutSine.transform(blendProgress);

                      // Entrance mode values
                      // At dotRaw=1.0 (finish): size=11, alpha=1.0, glow=0.18, ring=0
                      final eSize = 3.0 + dotAppear * 8.0;
                      final eAlpha = 0.15 + dotAppear * 0.85;
                      final eGlow = dotAppear * 0.18;
                      final eRing = (1.0 - dotAppear) * 0.18;

                      // Breathing mode values — baseline matches entrance final state
                      // so the transition is naturally continuous
                      final bSize = 11.0 + breath * 2.0;
                      final bAlpha = 1.0;
                      final bGlow = 0.12 + breath * 0.06;
                      const bRing = 0.0;

                      // Blend between entrance and breathing
                      final size = eSize + (bSize - eSize) * blendCurve;
                      final coreAlpha = eAlpha + (bAlpha - eAlpha) * blendCurve;
                      final glowAlpha = eGlow + (bGlow - eGlow) * blendCurve;
                      final ringAlpha = eRing + (bRing - eRing) * blendCurve;

                      return Padding(
                        padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                        child: _GapLoaderDot(
                          size: size,
                          coreAlpha: coreAlpha,
                          glowAlpha: glowAlpha,
                          ringAlpha: ringAlpha,
                        ),
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GapLoaderDot extends StatelessWidget {
  final double size;
  final double coreAlpha;
  final double glowAlpha;
  final double ringAlpha;

  const _GapLoaderDot({
    required this.size,
    required this.coreAlpha,
    required this.glowAlpha,
    required this.ringAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final glowSize = size + 6.0;
    final boxSize = math.max(glowSize, 22.0);

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glowAlpha > 0)
            Container(
              width: glowSize,
              height: glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: glowAlpha),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: ringAlpha > 0
                  ? Border.all(
                      color: Colors.white.withValues(alpha: ringAlpha),
                      width: 0.8,
                    )
                  : null,
              color: Colors.white.withValues(alpha: coreAlpha),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:math' as math;

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
        child: FractionallySizedBox(
          widthFactor: 0.92,
          alignment: Alignment.centerLeft,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final overallProgress = _controller.value;
                final exitBoost = Interval(
                  0.86,
                  1.0,
                  curve: Curves.easeOutCubic,
                ).transform(overallProgress);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final start = index / 3;
                    final end = (index + 1) / 3;
                    final progress =
                        Interval(start, end, curve: Curves.easeInOutCubic)
                            .transform(overallProgress);
                    final postFillProgress = overallProgress <= end
                        ? 0.0
                        : ((overallProgress - end) / (1 - end)).clamp(0.0, 1.0);
                    return Padding(
                      padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                      child: _GapLoaderDot(
                        progress: progress,
                        postFillProgress: postFillProgress,
                        dotIndex: index,
                        exitBoost: exitBoost,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GapLoaderDot extends StatelessWidget {
  final double progress;
  final double postFillProgress;
  final int dotIndex;
  final double exitBoost;

  const _GapLoaderDot({
    required this.progress,
    required this.postFillProgress,
    required this.dotIndex,
    required this.exitBoost,
  });

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final activeProgress = Curves.easeOutCubic.transform(clampedProgress);
    final isFilled = clampedProgress >= 0.999;
    final pulseWave = isFilled
        ? (math.sin(
                  ((postFillProgress * 2.8) + (dotIndex * 0.16)) * math.pi * 2,
                ) +
                1) /
            2
        : 0.0;
    final pulseProgress =
        isFilled ? Curves.easeInOutSine.transform(pulseWave) : 0.0;
    final finalPop = Curves.easeOutBack.transform(exitBoost.clamp(0.0, 1.0));

    final baseSize = 5.2;
    final activeSize = baseSize + (4.8 * activeProgress);
    final pulseSize = isFilled ? (7.6 + (3.8 * pulseProgress)) : activeSize;
    final size = pulseSize + (isFilled ? 4.8 * finalPop : 2.4 * finalPop);
    final glowSize = size + (isFilled ? 5.6 : 2.8 * activeProgress);
    final coreAlpha = isFilled
        ? (0.8 + (0.16 * pulseProgress) + (0.04 * exitBoost)).clamp(0.0, 1.0)
        : 0.18 + (0.74 * activeProgress);
    final glowAlpha = isFilled
        ? (0.05 + (0.14 * pulseProgress) + (0.07 * exitBoost)).clamp(0.0, 1.0)
        : 0.04 + (0.1 * activeProgress);
    final ringAlpha = isFilled ? 0.0 : 0.14 * (1 - activeProgress);

    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: glowSize,
            height: glowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(
                alpha: glowAlpha,
              ),
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
              color: Colors.white.withValues(
                alpha: coreAlpha,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

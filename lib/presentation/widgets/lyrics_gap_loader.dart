import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/player_tokens.dart';

/// Three dots that fill one at a time across an instrumental gap, so a full row
/// means the next lyric is about to land.
///
/// Everything is a function of [progress] — the fraction of the gap window that
/// has elapsed — rather than a self-running controller, because the pane feeds
/// this from the playback position and the gap length is not known up front.
class LyricsGapLoader extends StatefulWidget {
  /// 0 when the loader appears, 1 as the next lyric lands.
  final double progress;

  final Color accent;

  /// Fits the now-playing peek's single-line height instead of a full lyrics row.
  final bool compact;

  /// When non-null, shows a larger musical symbol filling bottom-to-top
  /// instead of the three pulsing dots. The string is a single glyph like "♪".
  final String? symbol;

  const LyricsGapLoader({
    super.key,
    required this.progress,
    required this.accent,
    this.compact = false,
    this.symbol,
  });

  @override
  State<LyricsGapLoader> createState() => _LyricsGapLoaderState();
}

class _LyricsGapLoaderState extends State<LyricsGapLoader>
    with SingleTickerProviderStateMixin {
  static const int _dotCount = 3;

  /// Dots finish filling before the end of the window, leaving room to pulse
  /// and clear out before the lyric arrives.
  static const double _fillEnd = 0.78;
  static const double _dotFillSpan = _fillEnd / _dotCount;

  static const double _enterEnd = 0.06;
  static const double _pulseEnd = 0.88;

  static const double _idleAlpha = 0.22;
  static const double _filledAlpha = 0.95;

  /// The position stream ticks about five times a second; this smooths those
  /// steps into continuous motion.
  static const Duration _smoothing = PlayerTokens.dLyricsInstrumentalFill;

  late final AnimationController _pulse;

  double get _idleSize => widget.compact ? 3.5 : 7.0;
  double get _filledSize => widget.compact ? 5.5 : 11.0;
  double get _dotGap => widget.compact ? 4.0 : 8.0;
  double get _glowPad => widget.compact ? 3.0 : 6.0;
  double get _minSlot => widget.compact ? 12.0 : 22.0;

  double get _noteSize => widget.compact ? 18.0 : 42.0;
  double get _noteSlot => widget.compact ? 24.0 : 52.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: PlayerTokens.dLyricsInstrumentalOscillation,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useNote = widget.symbol != null && widget.symbol!.isNotEmpty;
    final content = Align(
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: widget.progress),
        duration: _smoothing,
        curve: Curves.linear,
        builder: (context, p, _) {
          final enter = Curves.easeOut.transform(
            (p / _enterEnd).clamp(0.0, 1.0),
          );

          // One gentle swell once the row is full, then out of the way.
          final pulseRaw =
              ((p - _fillEnd) / (_pulseEnd - _fillEnd)).clamp(0.0, 1.0);
          final swell = math.sin(pulseRaw * math.pi) * 0.12;

          final exitRaw = ((p - _pulseEnd) / (1.0 - _pulseEnd)).clamp(0.0, 1.0);
          final exit = Curves.easeInCubic.transform(exitRaw);

          final opacity = enter * (1.0 - exit);
          final scale = (0.9 + enter * 0.1) * (1.0 + swell) - exit * 0.15;

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => useNote
                    ? _buildNote(widget.symbol!, p)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          _dotCount,
                          (index) => Padding(
                            padding: EdgeInsets.only(
                              right: index == _dotCount - 1 ? 0 : _dotGap,
                            ),
                            child: _buildDot(index, p),
                          ),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );

    return RepaintBoundary(
      child: widget.compact
          ? content
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: content,
            ),
    );
  }

  Widget _buildDot(int index, double p) {
    final fillRaw = ((p - index * _dotFillSpan) / _dotFillSpan).clamp(0.0, 1.0);
    final fill = Curves.easeOutCubic.transform(fillRaw);

    // Staggered breathing so a filled row still reads as "one by one".
    final phase = (_pulse.value + index * 0.33) * 2 * math.pi;
    final breath = math.sin(phase) * fill;

    return _GapLoaderDot(
      size: _idleSize + (_filledSize - _idleSize) * fill + breath * 0.35,
      coreAlpha:
          (_idleAlpha + (_filledAlpha - _idleAlpha) * fill + breath * 0.05)
              .clamp(0.0, 1.0),
      glowAlpha: fill * 0.16,
      glowPad: _glowPad,
      minSlot: _minSlot,
      accent: widget.accent,
    );
  }

  Widget _buildNote(String glyph, double p) {
    final fillRaw = (p / _fillEnd).clamp(0.0, 1.0);
    final fill = Curves.easeOutCubic.transform(fillRaw);
    final phase = _pulse.value * 2 * math.pi;
    final breath = math.sin(phase) * fill * 0.08;

    final glowAlpha = fill * 0.14;
    final glowSize = _noteSize + _glowPad + breath * 4;

    return SizedBox(
      width: _noteSlot,
      height: _noteSlot,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glowAlpha > 0)
            Container(
              width: glowSize,
              height: glowSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accent.withValues(alpha: glowAlpha),
              ),
            ),
          SizedBox(
            width: _noteSize,
            height: _noteSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  glyph,
                  style: TextStyle(
                    fontSize: _noteSize,
                    height: 1.0,
                    color: Colors.white.withValues(alpha: _idleAlpha),
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: fill.clamp(0.0, 1.0),
                    child: Text(
                      glyph,
                      style: TextStyle(
                        fontSize: _noteSize,
                        height: 1.0,
                        color: widget.accent.withValues(alpha: _filledAlpha),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GapLoaderDot extends StatelessWidget {
  final double size;
  final double coreAlpha;
  final double glowAlpha;
  final double glowPad;
  final double minSlot;
  final Color accent;

  const _GapLoaderDot({
    required this.size,
    required this.coreAlpha,
    required this.glowAlpha,
    required this.glowPad,
    required this.minSlot,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final glowSize = size + glowPad;
    // Fixed slot, so growing dots never reflow the row.
    final boxSize = math.max(glowSize, minSlot);

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
                color: accent.withValues(alpha: glowAlpha),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: coreAlpha),
            ),
          ),
        ],
      ),
    );
  }
}

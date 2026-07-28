import 'package:flutter/material.dart';

/// Title text that prefers shrinking over wrapping.
///
/// Fits on one line by reducing [style]'s font size down to [minFontSize].
/// Only when that still overflows does it wrap up to [maxLines].
class ShrinkThenWrapText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double minFontSize;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  const ShrinkThenWrapText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize = 16,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return Text(
            text,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
            style: style,
          );
        }

        final baseSize = style.fontSize ?? 14;
        final fittedSize = _largestSingleLineSize(
          text: text,
          style: style,
          maxWidth: maxWidth,
          maxSize: baseSize,
          minSize: minFontSize,
        );

        if (fittedSize != null) {
          return Text(
            text,
            maxLines: 1,
            overflow: overflow,
            textAlign: textAlign,
            style: style.copyWith(fontSize: fittedSize),
          );
        }

        return Text(
          text,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
          style: style.copyWith(fontSize: minFontSize),
        );
      },
    );
  }

  /// Binary-searches the largest font size in [[minSize], [maxSize]] that fits
  /// on one line. Returns null when even [minSize] overflows.
  static double? _largestSingleLineSize({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxSize,
    required double minSize,
  }) {
    if (_fitsOneLine(text, style.copyWith(fontSize: maxSize), maxWidth)) {
      return maxSize;
    }
    if (!_fitsOneLine(text, style.copyWith(fontSize: minSize), maxWidth)) {
      return null;
    }

    var low = minSize;
    var high = maxSize;
    // Quarter-point steps are enough for title type; tighter isn't visible.
    while (high - low > 0.25) {
      final mid = (low + high) / 2;
      if (_fitsOneLine(text, style.copyWith(fontSize: mid), maxWidth)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  static bool _fitsOneLine(String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    return painter.width <= maxWidth;
  }
}

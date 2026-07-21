import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/player_tokens.dart';

/// The single blurred-glass container used across the unified player.
///
/// Nothing else in the player may build its own BackdropFilter box — routing
/// every raised surface through here is what keeps the pill, the cards and the
/// transport dock reading as the same material.
class PlayerGlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool strong;
  final bool bordered;
  final Color? tint;

  const PlayerGlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PlayerTokens.s4),
    this.borderRadius,
    this.strong = false,
    this.bordered = true,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? PlayerTokens.brLg;
    final fillAlpha = strong
        ? PlayerTokens.glassFillAlphaStrong
        : PlayerTokens.glassFillAlpha;

    final baseFill = Colors.white.withValues(alpha: fillAlpha * 0.12);
    final fill = tint != null
        ? Color.alphaBlend(tint!.withValues(alpha: 0.10), baseFill)
        : baseFill;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: PlayerTokens.glassBlur,
          sigmaY: PlayerTokens.glassBlur,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Colors.black.withValues(alpha: fillAlpha),
              fill,
            ),
            borderRadius: radius,
            border: bordered
                ? Border.all(
                    color: Colors.white
                        .withValues(alpha: PlayerTokens.glassBorderAlpha),
                    width: 0.8,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

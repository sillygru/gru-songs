import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// The app's tap feedback for surfaces that shouldn't scale (rows, cards, sheet
/// actions): a quick tonal highlight under the finger instead of a Material ink
/// ripple. It's what makes a tap read as iOS-native rather than stock Flutter —
/// the whole surface responds and it clears the instant you lift or scroll.
///
/// For small controls that *should* spring, use `Pressable` instead.
class PressHighlight extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  PressHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    BorderRadius? borderRadius,
  }) : borderRadius = borderRadius ?? AppTokens.brMd;

  @override
  State<PressHighlight> createState() => _PressHighlightState();
}

class _PressHighlightState extends State<PressHighlight> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: AppTokens.dFast,
                curve: AppTokens.cStandard,
                decoration: BoxDecoration(
                  color: _pressed
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

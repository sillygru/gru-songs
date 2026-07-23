import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../tokens/app_tokens.dart';

/// The haptic played when a [Pressable] is tapped.
enum PressHaptic {
  none,
  selection,
  light,
  medium;

  void fire() {
    switch (this) {
      case PressHaptic.none:
        break;
      case PressHaptic.selection:
        HapticFeedback.selectionClick();
      case PressHaptic.light:
        HapticFeedback.lightImpact();
      case PressHaptic.medium:
        HapticFeedback.mediumImpact();
    }
  }
}

/// A tap target that dips under the finger and springs back — the app's
/// standard press feedback, used in place of a Material ink ripple.
///
/// The scale is driven by a [SpringSimulation], not a tween, so it is
/// *interruptible*: press-in, press-out, and a quick re-press all retarget from
/// the current scale and velocity instead of restarting from a fixed value.
/// Hold your finger down and the surface stays dipped; lift and it eases back
/// carrying whatever velocity it had. That is the "hold it mid-animation" feel
/// the whole revamp is built around, and it is why there is no ink splash here —
/// the motion is the feedback.
///
/// Wrap anything tappable: nav destinations, cards, list rows, icon buttons.
class Pressable extends StatefulWidget {
  final Widget child;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The spring driving the dip and rebound. [AppTokens.springSnappy] is the
  /// default; use [AppTokens.springGentle] for larger surfaces that can carry a
  /// little overshoot.
  final SpringDescription spring;

  /// Scale while held. Defaults to [AppTokens.pressScale].
  final double pressedScale;

  /// Haptic fired on tap (not on press-down, so a scroll that starts on this
  /// widget doesn't buzz). Defaults to a light impact.
  final PressHaptic haptic;

  /// Long-press always fires a medium impact when it triggers.
  final Alignment alignment;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.spring = AppTokens.springSnappy,
    this.pressedScale = AppTokens.pressScale,
    this.haptic = PressHaptic.light,
    this.alignment = Alignment.center,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    // Unbounded so the spring can overshoot past 1.0 without being clamped.
    _controller = AnimationController.unbounded(value: 1, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _controller.animateWith(
      SpringSimulation(
        widget.spring,
        _controller.value,
        target,
        _controller.velocity,
      ),
    );
  }

  void _handleTapDown(TapDownDetails _) => _springTo(widget.pressedScale);
  void _handleTapUp(TapUpDetails _) => _springTo(1);
  void _handleTapCancel() => _springTo(1);

  void _handleTap() {
    widget.haptic.fire();
    widget.onTap?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    widget.onLongPress!.call();
  }

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: _controller.value,
        alignment: widget.alignment,
        child: child,
      ),
      child: widget.child,
    );

    if (!_interactive) return scaled;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: scaled,
    );
  }
}

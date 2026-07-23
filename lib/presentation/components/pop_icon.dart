import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_tokens.dart';

/// A toggle icon that pops when tapped — squash, overshoot, then settle — with
/// an accent ring that blooms outward the moment it becomes active.
///
/// This is the player's favourite-heart animation lifted out so every like /
/// favourite / bookmark in the app pops the same way instead of just swapping
/// a glyph. The dip before the grow is what makes it read as a *press* rather
/// than a plain scale-up.
///
/// The active state is owned by the caller (usually a provider); [onTap]
/// performs the toggle, and this widget animates in response to [isActive]
/// flipping.
class PopIcon extends StatefulWidget {
  final bool isActive;
  final IconData activeIcon;
  final IconData inactiveIcon;

  /// Accent used for the active glyph and the bloom ring.
  final Color activeColor;
  final Color? inactiveColor;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  final double size;

  /// Overall tap target; defaults to [size] + breathing room.
  final double? hitSize;

  const PopIcon({
    super.key,
    required this.isActive,
    required this.onTap,
    this.activeIcon = Icons.favorite_rounded,
    this.inactiveIcon = Icons.favorite_border_rounded,
    required this.activeColor,
    this.inactiveColor,
    this.onLongPress,
    this.size = 28,
    this.hitSize,
  });

  @override
  State<PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<PopIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pop;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringFade;
  bool _showRing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _pop = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.78)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.78, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 56,
      ),
    ]).animate(_controller);

    _ringScale = Tween<double>(begin: 0.35, end: 1.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );
    _ringFade = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.65)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Both directions pop; only turning *on* gets the ring.
    _showRing = !widget.isActive;
    HapticFeedback.mediumImpact();
    widget.onTap();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hit = widget.hitSize ?? widget.size + 20;
    final inactive = widget.inactiveColor ?? AppTokens.fg(AppTokens.aSecondary);

    return InkResponse(
      radius: hit / 2,
      onTap: _handleTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: SizedBox(
        width: hit,
        height: hit,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (_showRing && _controller.isAnimating && _ringFade.value > 0)
                  Transform.scale(
                    scale: _ringScale.value,
                    child: Container(
                      width: widget.size + 2,
                      height: widget.size + 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.activeColor
                              .withValues(alpha: _ringFade.value),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                Transform.scale(scale: _pop.value, child: child),
              ],
            );
          },
          child: Icon(
            widget.isActive ? widget.activeIcon : widget.inactiveIcon,
            size: widget.size,
            color: widget.isActive ? widget.activeColor : inactive,
          ),
        ),
      ),
    );
  }
}

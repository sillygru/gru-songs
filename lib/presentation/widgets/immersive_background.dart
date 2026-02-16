import 'dart:ui';
import 'package:flutter/material.dart';

class ImmersiveBackground extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double blur;
  final double opacity;

  const ImmersiveBackground({
    super.key,
    required this.child,
    this.color,
    this.blur = 80,
    this.opacity = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? theme.colorScheme.primary;

    return Stack(
      children: [
        // Background Glow
        Positioned.fill(
          child: Container(
            color: theme.scaffoldBackgroundColor,
          ),
        ),
        Positioned(
          top: -250,
          left: -150,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  baseColor.withValues(alpha: 0.2),
                  baseColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -150,
          right: -150,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  baseColor.withValues(alpha: 0.15),
                  baseColor.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.3),
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

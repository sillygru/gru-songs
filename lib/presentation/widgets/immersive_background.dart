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
          top: -200,
          left: -100,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseColor.withValues(alpha: 0.15),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          right: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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
        ),
        child,
      ],
    );
  }
}

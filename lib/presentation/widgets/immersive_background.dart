import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import 'smooth_color_builder.dart';

/// The app-wide immersive backdrop.
///
/// Depth here comes from light, not from glass: two large, soft radial blooms
/// tinted by the *current cover's* extracted colour, floating over the near-black
/// scaffold, with a gentle top→bottom darkening so foreground text stays legible.
/// There is no [BackdropFilter], no border and no shadow anywhere in this file.
///
/// The bloom colour is the same value the player and every accent read from
/// ([themeProvider.extractedColor]), and it crossfades through
/// [SmoothColorBuilder] as the track changes — so the whole app breathes with
/// the music instead of sitting on a static theme glow.
class AmbientLayer extends ConsumerWidget {
  /// Force a specific tint instead of the live cover colour. Used by screens
  /// that want to key off their own artwork rather than what is playing.
  final Color? colorOverride;

  /// Scales every bloom's strength. 1 = default; lower for busy screens.
  final double intensity;

  const AmbientLayer({
    super.key,
    this.colorOverride,
    this.intensity = 1.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extracted = ref.watch(themeProvider.select((s) => s.extractedColor));
    final target = colorOverride ?? extracted ?? theme.colorScheme.primary;

    return SmoothColorBuilder(
      targetColor: target,
      builder: (context, color) {
        return RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: theme.scaffoldBackgroundColor),
              ),
              // Top-left bloom — the loud one.
              Positioned(
                top: -260,
                left: -160,
                child: _Bloom(
                  size: 620,
                  colors: [
                    color.withValues(alpha: 0.22 * intensity),
                    color.withValues(alpha: 0.10 * intensity),
                    Colors.transparent,
                  ],
                ),
              ),
              // Bottom-right bloom — quieter, anchors the other corner.
              Positioned(
                bottom: -200,
                right: -160,
                child: _Bloom(
                  size: 520,
                  colors: [
                    color.withValues(alpha: 0.16 * intensity),
                    color.withValues(alpha: 0.06 * intensity),
                    Colors.transparent,
                  ],
                ),
              ),
              // Legibility wash — keeps the lower half readable over the blooms.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
                        theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
                      ],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bloom extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _Bloom({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: colors,
          stops: const [0.2, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// Wraps [child] over the [AmbientLayer]. Kept as the drop-in the root shell
/// uses; sub-screens reach for `AmbientScaffold` instead.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final Color? colorOverride;

  const AmbientBackground({
    super.key,
    required this.child,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: AmbientLayer(colorOverride: colorOverride)),
        child,
      ],
    );
  }
}

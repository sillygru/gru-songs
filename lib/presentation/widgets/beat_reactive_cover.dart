import 'package:flutter/widgets.dart';

import '../tokens/player_tokens.dart';
import 'player_motion.dart';

/// Scales the album artwork with the beat.
///
/// Three things combine, in decreasing size:
///
///  * a continuous breath on the beat period, so the cover is never still;
///  * a punch on each beat, harder on downbeats;
///  * a small contraction in the ~60 ms *before* each beat.
///
/// That last one is the difference between "reacting to audio" and "moving with
/// the music" — it is the anticipation a person shows nodding along, and it is
/// only possible because the beat grid was computed ahead of time.
///
/// The base scale is 1.0. Anything less permanently shrinks the artwork, which
/// is what the first version of this feature did.
class BeatReactiveCover extends StatelessWidget {
  final PlayerMotionController controller;
  final Color accent;
  final bool enabled;
  final Widget child;

  const BeatReactiveCover({
    super.key,
    required this.controller,
    required this.accent,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return ListenableBuilder(
      listenable: controller,
      // The artwork subtree is passed through untouched, so a beat repaints the
      // transform without rebuilding the image.
      child: child,
      builder: (context, child) {
        final frame = controller.frame;
        final spec = controller.spec;

        final scale = 1.0 +
            frame.breath * spec.coverBreath +
            frame.displacement * spec.coverPunch;

        // Glow tracks the punch only. Tying it to the breath as well would
        // leave a permanent halo, which reads as a bug rather than an accent.
        final glow = frame.pulse;

        return Transform.scale(
          scale: scale,
          child: Stack(
            children: [
              if (glow > 0.01)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: PlayerTokens.brLg,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.34 * glow),
                            blurRadius: 18 + 42 * glow,
                            spreadRadius: 6 * glow,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
    );
  }
}

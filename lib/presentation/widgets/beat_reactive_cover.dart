import 'package:flutter/widgets.dart';

import 'player_motion.dart';

/// Moves the album artwork with the beat.
///
/// Four things combine, in decreasing size:
///
///  * a continuous breath on the beat period, so the cover is never still;
///  * a punch on each beat, harder on downbeats and weighted by how much low end
///    that moment actually has — a kick moves the artwork, a hi-hat barely does;
///  * a small contraction in the ~60 ms *before* each beat;
///  * an overshoot past rest afterwards, and a lean that alternates side to side
///    at a slightly different depth every beat.
///
/// The anticipation is the difference between "reacting to audio" and "moving
/// with the music" — it is what a person does nodding along, and it is only
/// possible because the beat grid was computed ahead of time. The rest exists
/// because nothing physical returns to rest in a straight line, and nothing
/// human repeats a gesture identically.
///
/// The base scale is 1.0. Anything less permanently shrinks the artwork, which
/// is what the first version of this feature did.
///
/// The glow is *not* here: it lives in the player shell as `BeatCoverGlow`, so
/// it can spill past this pane instead of being clipped at its edge.
class BeatReactiveCover extends StatelessWidget {
  final PlayerMotionController controller;
  final bool enabled;
  final Widget child;

  const BeatReactiveCover({
    super.key,
    required this.controller,
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

        // One matrix rather than nested Transforms: three stacked transforms
        // would mean three layers for what is one gesture.
        final displacement = frame.displacement * (0.85 + 0.3 * frame.bass);
        final scale = 1.0 +
            frame.breath * spec.coverBreath +
            displacement * spec.coverPunch;

        final matrix = Matrix4.identity()
          // Negative Y is up: the cover rides up on the punch and sinks into
          // the anticipation.
          ..translateByDouble(0, -displacement * spec.coverLift, 0, 1)
          ..rotateZ(frame.sway * spec.coverSway)
          ..scaleByDouble(scale, scale, 1, 1);

        return Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: child,
        );
      },
    );
  }
}

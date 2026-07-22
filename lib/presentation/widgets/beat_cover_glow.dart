import 'package:flutter/widgets.dart';

import '../tokens/player_tokens.dart';
import 'player_motion.dart';

/// The accent glow that flares behind the album artwork on every beat.
///
/// Lives in the player shell rather than inside [BeatReactiveCover], because a
/// glow drawn inside the cover cannot escape it: the pane sits in a [PageView],
/// whose viewport clips, so the light was being sliced off flat at the pane's
/// edge — right under the segmented pill and above the transport dock. Painted
/// here it spills across the whole screen, and sitting below the shell's content
/// column it stays behind the pill, title and controls rather than hazing them.
///
/// Geometry is read straight off the render tree each paint instead of being
/// mirrored into a notifier. That is one source of truth, and it comes for free:
/// the key sits *inside* the cover's beat transform, so the glow tracks the
/// pulse scale, the page swipe, rotation and the Hero flight without any of
/// those having to know this layer exists.
class BeatCoverGlow extends StatelessWidget {
  final PlayerMotionController controller;

  /// The artwork box. Anything that is not currently on screen (video mode, a
  /// pane that has not been built) simply yields no glow.
  final GlobalKey coverKey;

  /// The shell's own stack, used to convert the artwork into this layer's
  /// coordinates.
  final GlobalKey shellKey;

  final Color accent;

  const BeatCoverGlow({
    super.key,
    required this.controller,
    required this.coverKey,
    required this.shellKey,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CoverGlowPainter(
            controller: controller,
            coverKey: coverKey,
            shellKey: shellKey,
            accent: accent,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CoverGlowPainter extends CustomPainter {
  final PlayerMotionController controller;
  final GlobalKey coverKey;
  final GlobalKey shellKey;
  final Color accent;

  final Paint _paint = Paint();

  _CoverGlowPainter({
    required this.controller,
    required this.coverKey,
    required this.shellKey,
    required this.accent,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    // Tied to the punch only. Tying it to the breath as well would leave a
    // permanent halo, which reads as a bug rather than an accent.
    final glow = controller.frame.pulse;
    if (glow < 0.01) return;

    final rect = _coverRect();
    if (rect == null || rect.isEmpty) return;

    // Swiping to Lyrics or Queue carries the artwork a page off screen, and a
    // glow with no visible source to explain it just looks like a leak at the
    // edge. Fade with how much of the cover is actually on screen, which also
    // means the light follows the swipe out rather than cutting off.
    final visible = _visibleFraction(rect, size);
    if (visible <= 0.01) return;

    // Same recipe the BoxShadow inside the cover used, so only the clipping
    // changed and not the look.
    final blurRadius = 18 + 42 * glow;
    _paint
      ..color = accent.withValues(alpha: 0.34 * glow * visible * visible)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        Shadow.convertRadiusToSigma(blurRadius),
      );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(6 * glow),
        const Radius.circular(PlayerTokens.rLg),
      ),
      _paint,
    );
  }

  /// How much of [rect] lies within the layer, 0..1.
  double _visibleFraction(Rect rect, Size size) {
    if (rect.width <= 0) return 0;
    final left = rect.left.clamp(0.0, size.width);
    final right = rect.right.clamp(0.0, size.width);
    return ((right - left) / rect.width).clamp(0.0, 1.0);
  }

  /// The artwork's current bounds in this layer's coordinates, or null when
  /// there is nothing on screen to glow behind.
  ///
  /// Resolved through the root rather than with `getTransformTo(shellBox)`:
  /// during a Hero flight the artwork is re-parented into the overlay and is no
  /// longer a descendant of the shell, which that form asserts on.
  Rect? _coverRect() {
    final cover = coverKey.currentContext?.findRenderObject();
    final shell = shellKey.currentContext?.findRenderObject();
    if (cover is! RenderBox || shell is! RenderBox) return null;
    if (!cover.attached || !shell.attached) return null;
    if (!cover.hasSize || !shell.hasSize) return null;

    final global = MatrixUtils.transformRect(
      cover.getTransformTo(null),
      Offset.zero & cover.size,
    );
    return global.shift(-shell.localToGlobal(Offset.zero));
  }

  @override
  bool shouldRepaint(_CoverGlowPainter oldDelegate) {
    // Repaint is driven by the controller via `repaint:`; this only matters when
    // the widget itself is rebuilt, e.g. the accent changing between tracks.
    return oldDelegate.accent != accent;
  }

  @override
  bool shouldRebuildSemantics(_CoverGlowPainter oldDelegate) => false;
}

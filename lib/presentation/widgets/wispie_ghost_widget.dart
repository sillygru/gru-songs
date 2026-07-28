import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens/app_tokens.dart';

enum GhostExpression {
  happy,
  excited,
  appearance,
  searching,
  celebrate,
}

class WispieGhostWidget extends StatefulWidget {
  final String speechText;
  final GhostExpression expression;
  final double ghostSize;
  final bool showSpeechBubble;

  /// When true (default) the ghost breathes, bobs and drifts on its own.
  /// Set false while a parent choreographs a one-shot motion (entrance swoop,
  /// fly-away) so the ghost holds still instead of fighting the parent's
  /// transforms. Blinking, gaze, aura and expression changes still play.
  final bool idleFloat;

  const WispieGhostWidget({
    super.key,
    required this.speechText,
    this.expression = GhostExpression.happy,
    this.ghostSize = 130,
    this.showSpeechBubble = true,
    this.idleFloat = true,
  });

  @override
  State<WispieGhostWidget> createState() => _WispieGhostWidgetState();
}

class _WispieGhostWidgetState extends State<WispieGhostWidget>
    with TickerProviderStateMixin {
  // Body bob + sway + squash. Integer harmonics only, so repeat() wraps with
  // no visible hitch.
  late final AnimationController _floatController;
  // Slow lateral wander on a coprime period (6s x 11s => retraces every 66s).
  late final AnimationController _driftController;
  // Aura inhale/exhale + body breathing scale + blush pulse.
  late final AnimationController _breathController;
  // One-shot blink (asymmetric close/open).
  late final AnimationController _blinkController;
  // One-shot expression squish-swap transition.
  late final AnimationController _expressionController;
  // One-shot speech-bubble enter/exit (fade + scale + rise).
  late final AnimationController _bubbleController;
  // Continuous eye-gaze wandering (saccade-like, integer harmonics).
  late final AnimationController _gazeController;
  // Smooth ramp when enabling/disabling idle floating.
  late final AnimationController _idleRampController;

  Timer? _blinkTimer;
  GhostExpression _previousExpression = GhostExpression.happy;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _previousExpression = widget.expression;

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 11000),
    )..repeat();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _expressionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: 1.0,
    );

    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: widget.showSpeechBubble ? 1.0 : 0.0,
    );

    _gazeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();

    _idleRampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.idleFloat ? 1.0 : 0.0,
    );

    _scheduleNextBlink();
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final nextBlinkMs = 3000 + _rng.nextInt(2600);
    _blinkTimer = Timer(Duration(milliseconds: nextBlinkMs), _doBlink);
  }

  void _doBlink() {
    if (!mounted) return;
    _blinkController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      // Occasional natural double-blink.
      if (_rng.nextDouble() < 0.22) {
        Timer(const Duration(milliseconds: 210), () {
          if (!mounted) return;
          _blinkController.forward(from: 0.0).then((_) {
            if (mounted) _scheduleNextBlink();
          });
        });
      } else {
        _scheduleNextBlink();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WispieGhostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression) {
      _previousExpression = oldWidget.expression;
      _expressionController.forward(from: 0.0);
    }
    if (oldWidget.showSpeechBubble != widget.showSpeechBubble) {
      if (widget.showSpeechBubble) {
        _bubbleController.forward(from: 0.0);
      } else {
        _bubbleController.reverse();
      }
    }
    if (oldWidget.idleFloat != widget.idleFloat) {
      if (widget.idleFloat) {
        _idleRampController.forward();
      } else {
        _idleRampController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _floatController.dispose();
    _driftController.dispose();
    _breathController.dispose();
    _blinkController.dispose();
    _expressionController.dispose();
    _bubbleController.dispose();
    _gazeController.dispose();
    _idleRampController.dispose();
    super.dispose();
  }

  // Asymmetric blink: snap shut (easeIn, fast) then ease open (slower).
  static double _blinkClosedness(double v) {
    if (v < 0.35) {
      return Curves.easeIn.transform(v / 0.35);
    }
    return 1.0 - Curves.easeOut.transform((v - 0.35) / 0.65);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _driftController,
        _breathController,
        _blinkController,
        _expressionController,
        _bubbleController,
        _gazeController,
        _idleRampController,
      ]),
      builder: (context, child) {
        final t = _floatController.value * math.pi * 2;
        final d = _driftController.value * math.pi * 2;
        final breath = _breathController.value * math.pi * 2;
        final g = _gazeController.value * math.pi * 2;

        // During the squish-swap, the "effective" expression follows the
        // swap point so widget-level motion (bounce, tilt) matches the face.
        final exprProgress = _expressionController.value;
        final effectiveExpr =
            exprProgress < 0.5 ? _previousExpression : widget.expression;

        double offsetX = 0;
        double offsetY = 0;
        double rotation = 0;
        double scaleX = 1;
        double scaleY = 1;

        final floatRamp = Curves.easeInOut.transform(_idleRampController.value);

        if (floatRamp > 0) {
          // Vertical: primary bob + tertiary ripple. Integer harmonics.
          offsetY = (math.sin(t) * 8.0 + math.sin(3 * t) * 1.5) * floatRamp;
          // Lateral: faster sway + slow wander, decorrelated from vertical.
          offsetX = (math.cos(2 * t) * 3.0 + math.sin(d) * 4.5) * floatRamp;
          offsetY += (math.cos(d) * 2.0) * floatRamp;

          // Squash & stretch driven by vertical velocity.
          final yVel = math.cos(t) + 3 * math.cos(3 * t) * 0.18;
          scaleY = 1.0 + (yVel * 0.025) * floatRamp;
          scaleX = 1.0 - (yVel * 0.018) * floatRamp;

          // Tilt lags the bob so the body leans into its drift.
          rotation =
              (math.sin(t - 1.1) * 0.03 + math.sin(d) * 0.012) * floatRamp;

          // Expression-specific idle energy.
          if (effectiveExpr == GhostExpression.excited ||
              effectiveExpr == GhostExpression.celebrate) {
            // Energetic bouncy hops (abs-sine => bounce, not swing).
            offsetY += math.sin(2 * t).abs() * 3.0 * floatRamp;
          } else if (effectiveExpr == GhostExpression.searching) {
            // Slow head tilt scanning side to side.
            rotation += math.sin(2 * t) * 0.06 * floatRamp;
          }
        }

        // Breathing body scale (subtle inhale/exhale, independent of float).
        final breathScale = 0.5 + 0.5 * math.sin(breath);
        scaleY *= 1.0 + breathScale * 0.012;
        scaleX *= 1.0 - breathScale * 0.008;

        // Expression squish-swap: compress vertically at mid-transition,
        // bulge horizontally. The face swaps at the nadir (progress ≈ 0.5).
        final squish = math.sin(exprProgress * math.pi);
        scaleY *= 1.0 - squish * 0.10;
        scaleX *= 1.0 + squish * 0.07;

        final blinkClosed = _blinkClosedness(_blinkController.value);

        // Gaze wandering (integer harmonics => seamless loop).
        double gazeX = math.sin(g) * 0.6 + math.sin(3 * g + 1.5) * 0.3;
        double gazeY = math.cos(2 * g + 0.7) * 0.4;
        // Searching: wider horizontal scanning, less vertical.
        if (effectiveExpr == GhostExpression.searching) {
          gazeX *= 1.5;
          gazeY *= 0.4;
        }
        final bubbleScale = Curves.easeOutBack
            .transform(_bubbleController.value.clamp(0.0, 1.0));
        final bubbleOpacity = _bubbleController.value.clamp(0.0, 1.0);

        // Column-based layout with a zero-height bubble slot so the ghost
        // stays vertically centered regardless of whether the bubble is
        // shown. The OverflowBox inside the 0-height slot lets the bubble
        // render at its natural size (extending upward) without affecting
        // the Column's total height.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bubble slot — 0 height so it doesn't shift the ghost down.
            // OverflowBox: sizes itself to the tight 0-height constraints but
            // passes unbounded constraints to the child, letting the bubble
            // be as wide/tall as its text needs and extending upward.
            SizedBox(
              height: 0,
              width: widget.ghostSize,
              child: OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  // Float gently with the ghost; -12 creates the gap.
                  offset: Offset(offsetX * 0.5, offsetY * 0.6 - 12),
                  child: Opacity(
                    opacity: bubbleOpacity,
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * bubbleScale,
                      alignment: Alignment.bottomCenter,
                      child: Transform.translate(
                        offset: Offset(0, (1 - _bubbleController.value) * 14),
                        child: _SpeechBubble(text: widget.speechText),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Ghost body — the Column's height is just the ghost's height,
            // so the parent centers the ghost (not ghost+bubble).
            Transform.translate(
              offset: Offset(offsetX, offsetY),
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scaleX: scaleX,
                  scaleY: scaleY,
                  child: SizedBox(
                    width: widget.ghostSize,
                    height: widget.ghostSize,
                    child: CustomPaint(
                      painter: _GhostPainter(
                        expression: widget.expression,
                        previousExpression: _previousExpression,
                        expressionProgress: exprProgress,
                        floatAnimValue:
                            widget.idleFloat ? _floatController.value : 0.0,
                        blinkValue: blinkClosed,
                        breathValue: breathScale,
                        gazeX: gazeX,
                        gazeY: gazeY,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Constrain max width so the bubble never goes off screen horizontally.
    final maxBubbleWidth = math.min(340.0, math.max(160.0, screenWidth - 48.0));

    return AnimatedSwitcher(
      duration: AppTokens.dBase,
      switchInCurve: AppTokens.cEmphasized,
      switchOutCurve: AppTokens.cStandard,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: Stack(
        key: ValueKey<String>(text),
        alignment: Alignment.bottomCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxBubbleWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppTokens.surface(2),
                borderRadius: AppTokens.brLg,
                boxShadow: AppTokens.shadowRaised,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: AppTokens.fgPrimary,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 2,
            child: CustomPaint(
              size: const Size(14, 8),
              painter: _BubbleTailPainter(color: AppTokens.surface(2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;

  _BubbleTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _GhostPainter extends CustomPainter {
  final GhostExpression expression;
  final GhostExpression previousExpression;
  final double expressionProgress;
  final double floatAnimValue;
  final double blinkValue;
  final double breathValue;
  final double gazeX;
  final double gazeY;

  _GhostPainter({
    required this.expression,
    required this.previousExpression,
    required this.expressionProgress,
    required this.floatAnimValue,
    required this.blinkValue,
    required this.breathValue,
    required this.gazeX,
    required this.gazeY,
  });

  // The face swaps at the nadir of the squish (progress ≈ 0.5).
  GhostExpression get _effective =>
      expressionProgress < 0.5 ? previousExpression : expression;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final expr = _effective;

    // 1. Soft lavender aura that breathes (inhale = larger + brighter).
    final auraAlpha = 0.18 + breathValue * 0.14;
    final auraRadius = w * (0.40 + breathValue * 0.06);
    final auraPaint = Paint()
      ..color = const Color(0xFFD8B4F8).withValues(alpha: auraAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(Offset(w / 2, h / 2), auraRadius, auraPaint);

    // 2. Main ghost body path.
    final bodyPaint = Paint()
      ..color = const Color(0xFFF6EEFF)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(w * 0.2, h * 0.5);
    path.cubicTo(w * 0.2, h * 0.08, w * 0.8, h * 0.08, w * 0.8, h * 0.5);
    path.lineTo(w * 0.82, h * 0.78);

    // Wavy bottom skirt folds (integer harmonic => seamless loop).
    final waveShift = math.sin(floatAnimValue * math.pi * 2) * 2.5;

    path.quadraticBezierTo(w * 0.74, h * 0.92 + waveShift, w * 0.65, h * 0.82);
    path.quadraticBezierTo(w * 0.55, h * 0.94 - waveShift, w * 0.45, h * 0.82);
    path.quadraticBezierTo(w * 0.35, h * 0.92 + waveShift, w * 0.25, h * 0.82);
    path.quadraticBezierTo(w * 0.18, h * 0.88, w * 0.18, h * 0.78);

    path.lineTo(w * 0.2, h * 0.5);
    path.close();
    canvas.drawPath(path, bodyPaint);

    // 3. Soft lavender shading overlay.
    final shadePaint = Paint()
      ..color = const Color(0xFFC7B3E5).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final shadePath = Path();
    shadePath.moveTo(w * 0.2, h * 0.65);
    shadePath.cubicTo(w * 0.2, h * 0.85, w * 0.8, h * 0.85, w * 0.8, h * 0.65);
    shadePath.lineTo(w * 0.82, h * 0.78);
    shadePath.quadraticBezierTo(
        w * 0.74, h * 0.92 + waveShift, w * 0.65, h * 0.82);
    shadePath.quadraticBezierTo(
        w * 0.55, h * 0.94 - waveShift, w * 0.45, h * 0.82);
    shadePath.quadraticBezierTo(
        w * 0.35, h * 0.92 + waveShift, w * 0.25, h * 0.82);
    shadePath.quadraticBezierTo(w * 0.18, h * 0.88, w * 0.18, h * 0.78);
    shadePath.close();
    canvas.drawPath(shadePath, shadePaint);

    // 4. Arms — per-expression poses.
    _drawArms(canvas, w, h, expr, floatAnimValue);

    // 5. Rosy blush cheeks — pulse with breathing.
    final blushAlpha = 0.50 + breathValue * 0.18;
    final blushPaint = Paint()
      ..color = const Color(0xFFFF94B9).withValues(alpha: blushAlpha)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.33, h * 0.43),
          width: w * 0.12,
          height: h * 0.07),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.67, h * 0.43),
          width: w * 0.12,
          height: h * 0.07),
      blushPaint,
    );

    // 6. Eyes & blinking with gaze tracking.
    _drawEyes(canvas, w, h, blinkValue, expr, gazeX, gazeY);

    // 7. Mouth — per-expression.
    _drawMouth(canvas, w, h, expr);
  }

  void _drawArms(
    Canvas canvas,
    double w,
    double h,
    GhostExpression expr,
    double floatVal,
  ) {
    final armPaint = Paint()
      ..color = const Color(0xFFEDE0FB)
      ..style = PaintingStyle.fill;

    // Relaxed left arm used by most expressions.
    final relaxedLeft = Path()
      ..moveTo(w * 0.22, h * 0.52)
      ..quadraticBezierTo(w * 0.1, h * 0.55, w * 0.14, h * 0.44)
      ..quadraticBezierTo(w * 0.22, h * 0.44, w * 0.24, h * 0.5);

    if (expr == GhostExpression.celebrate) {
      // Both arms raised, waving in opposition.
      final wave = math.sin(floatVal * math.pi * 4);
      final leftRaised = Path()
        ..moveTo(w * 0.22, h * 0.52)
        ..quadraticBezierTo(
            w * 0.06, h * 0.40 + wave * 4, w * 0.10, h * 0.26 + wave * 5)
        ..quadraticBezierTo(w * 0.22, h * 0.32, w * 0.24, h * 0.50);
      canvas.drawPath(leftRaised, armPaint);

      final rightRaised = Path()
        ..moveTo(w * 0.78, h * 0.52)
        ..quadraticBezierTo(
            w * 0.94, h * 0.40 - wave * 4, w * 0.90, h * 0.26 - wave * 5)
        ..quadraticBezierTo(w * 0.78, h * 0.32, w * 0.76, h * 0.50);
      canvas.drawPath(rightRaised, armPaint);
    } else if (expr == GhostExpression.happy ||
        expr == GhostExpression.excited) {
      canvas.drawPath(relaxedLeft, armPaint);

      // Right arm waving — excited waves faster and wider.
      final speed = expr == GhostExpression.excited ? 6 : 4;
      final amp = expr == GhostExpression.excited ? 6.0 : 4.0;
      final waveArmOffset = math.sin(floatVal * math.pi * speed) * amp;

      final rightArm = Path()
        ..moveTo(w * 0.78, h * 0.52)
        ..quadraticBezierTo(
          w * 0.92,
          h * 0.42 + waveArmOffset,
          w * 0.86,
          h * 0.34 + waveArmOffset,
        )
        ..quadraticBezierTo(w * 0.78, h * 0.38, w * 0.76, h * 0.5);
      canvas.drawPath(rightArm, armPaint);
    } else if (expr == GhostExpression.searching) {
      // Left arm relaxed; right arm raised slightly (looking pose).
      canvas.drawPath(relaxedLeft, armPaint);

      final rightArm = Path()
        ..moveTo(w * 0.78, h * 0.52)
        ..quadraticBezierTo(w * 0.88, h * 0.42, w * 0.82, h * 0.34)
        ..quadraticBezierTo(w * 0.76, h * 0.38, w * 0.76, h * 0.5);
      canvas.drawPath(rightArm, armPaint);
    } else {
      // appearance / default: both arms relaxed.
      canvas.drawPath(relaxedLeft, armPaint);

      final rightArm = Path()
        ..moveTo(w * 0.78, h * 0.52)
        ..quadraticBezierTo(w * 0.92, h * 0.46, w * 0.86, h * 0.38)
        ..quadraticBezierTo(w * 0.78, h * 0.42, w * 0.76, h * 0.5);
      canvas.drawPath(rightArm, armPaint);
    }
  }

  void _drawEyes(
    Canvas canvas,
    double w,
    double h,
    double blink,
    GhostExpression expr,
    double gazeX,
    double gazeY,
  ) {
    final eyeDarkPaint = Paint()
      ..color = const Color(0xFF2E2438)
      ..style = PaintingStyle.fill;

    final eyeSparkleBig = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final eyeSparkleSmall = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final closedEyePaint = Paint()
      ..color = const Color(0xFF2E2438)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    // Closed happy arc eyes for celebrate expression.
    if (expr == GhostExpression.celebrate) {
      final leftPath = Path()
        ..moveTo(w * 0.34, h * 0.40)
        ..quadraticBezierTo(w * 0.40, h * 0.34, w * 0.46, h * 0.40);
      final rightPath = Path()
        ..moveTo(w * 0.54, h * 0.40)
        ..quadraticBezierTo(w * 0.60, h * 0.34, w * 0.66, h * 0.40);
      canvas.drawPath(leftPath, closedEyePaint);
      canvas.drawPath(rightPath, closedEyePaint);
      return;
    }

    final blinkScaleY = (1.0 - blink).clamp(0.05, 1.0);

    if (blinkScaleY < 0.15) {
      final leftBlink = Path()
        ..moveTo(w * 0.34, h * 0.38)
        ..quadraticBezierTo(w * 0.40, h * 0.41, w * 0.46, h * 0.38);
      final rightBlink = Path()
        ..moveTo(w * 0.54, h * 0.38)
        ..quadraticBezierTo(w * 0.60, h * 0.41, w * 0.66, h * 0.38);
      canvas.drawPath(leftBlink, closedEyePaint);
      canvas.drawPath(rightBlink, closedEyePaint);
      return;
    }

    void drawSingleEye(double cx, double cy) {
      double eyeW = w * 0.11;
      double eyeH = h * 0.14 * blinkScaleY;

      // Expression-specific eye proportions.
      if (expr == GhostExpression.excited) {
        eyeW *= 1.15;
        eyeH *= 1.20;
      } else if (expr == GhostExpression.searching) {
        eyeH *= 0.85; // slightly squinted
      }

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: eyeW,
          height: eyeH,
        ),
        eyeDarkPaint,
      );

      if (blinkScaleY > 0.4) {
        // Sparkle positions shift with gaze, creating the impression of
        // looking around without a separate iris/pupil layer.
        final gx = gazeX * eyeW * 0.25;
        final gy = gazeY * eyeH * 0.25;

        // Big sparkle top-left.
        canvas.drawCircle(
          Offset(cx - eyeW * 0.18 + gx, cy - eyeH * 0.28 + gy),
          w * 0.032,
          eyeSparkleBig,
        );
        // Small sparkle bottom-right.
        canvas.drawCircle(
          Offset(cx + eyeW * 0.18 + gx, cy + eyeH * 0.22 + gy),
          w * 0.016,
          eyeSparkleSmall,
        );
      }
    }

    drawSingleEye(w * 0.4, h * 0.38);
    drawSingleEye(w * 0.6, h * 0.38);
  }

  void _drawMouth(Canvas canvas, double w, double h, GhostExpression expr) {
    final mouthPaint = Paint()
      ..color = const Color(0xFF2E2438)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    if (expr == GhostExpression.excited || expr == GhostExpression.celebrate) {
      // Open happy mouth.
      final openMouthPaint = Paint()
        ..color = const Color(0xFF2E2438)
        ..style = PaintingStyle.fill;
      final mouthPath = Path()
        ..moveTo(w * 0.45, h * 0.44)
        ..quadraticBezierTo(w * 0.5, h * 0.52, w * 0.55, h * 0.44)
        ..close();
      canvas.drawPath(mouthPath, openMouthPaint);
    } else if (expr == GhostExpression.searching) {
      // Small curious 'o' mouth.
      final oPaint = Paint()
        ..color = const Color(0xFF2E2438)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.47),
          width: w * 0.05,
          height: h * 0.035,
        ),
        oPaint,
      );
    } else {
      // Classic cute 'w' mouth (happy / appearance).
      final mouthPath = Path()
        ..moveTo(w * 0.43, h * 0.45)
        ..quadraticBezierTo(w * 0.465, h * 0.485, w * 0.5, h * 0.46)
        ..quadraticBezierTo(w * 0.535, h * 0.485, w * 0.57, h * 0.45);
      canvas.drawPath(mouthPath, mouthPaint);
    }
  }

  @override
  bool shouldRepaint(_GhostPainter oldDelegate) =>
      expression != oldDelegate.expression ||
      previousExpression != oldDelegate.previousExpression ||
      expressionProgress != oldDelegate.expressionProgress ||
      floatAnimValue != oldDelegate.floatAnimValue ||
      blinkValue != oldDelegate.blinkValue ||
      breathValue != oldDelegate.breathValue ||
      gazeX != oldDelegate.gazeX ||
      gazeY != oldDelegate.gazeY;
}

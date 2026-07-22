import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'player_motion.dart';

/// Floating particles that drift with the music and scatter on the beat.
///
/// Lives in the player shell rather than any one pane, so the whole screen —
/// lyrics, artwork and queue alike — shares the same field.
///
/// The motion is built to avoid the two things that make particle effects look
/// cheap: perfectly straight travel, and every particle doing the same thing at
/// the same time. Each one wanders on its own pair of out-of-phase sine
/// components, at its own depth, so the field reads as drifting dust rather
/// than confetti on glass.
class BeatParticleField extends StatefulWidget {
  final PlayerMotionController controller;
  final Color accent;

  const BeatParticleField({
    super.key,
    required this.controller,
    required this.accent,
  });

  @override
  State<BeatParticleField> createState() => _BeatParticleFieldState();
}

class _BeatParticleFieldState extends State<BeatParticleField> {
  late final _ParticleSystem _system = _ParticleSystem();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          // Repainting off the controller directly means this subtree never
          // rebuilds — the painter just redraws when a frame lands.
          painter: _ParticlePainter(
            controller: widget.controller,
            system: _system,
            accent: widget.accent,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// One drifting mote. Positions are normalised 0..1 so the simulation is
/// resolution independent and survives rotation without teleporting.
class _Particle {
  double x;
  double y;

  /// Velocity from beat impulses, in normalised units per second. Decays.
  double impulseX = 0;
  double impulseY = 0;

  /// 0 = far away, 1 = close. Drives size, speed, brightness and how much a
  /// shockwave moves it — near particles react hard, distant ones barely.
  final double depth;

  final double baseRadius;
  final double driftPhaseX;
  final double driftPhaseY;
  final double driftFreqX;
  final double driftFreqY;
  final double twinklePhase;
  final double twinkleRate;

  _Particle({
    required this.x,
    required this.y,
    required this.depth,
    required this.baseRadius,
    required this.driftPhaseX,
    required this.driftPhaseY,
    required this.driftFreqX,
    required this.driftFreqY,
    required this.twinklePhase,
    required this.twinkleRate,
  });
}

/// An expanding ring spawned on a beat. Particles it passes get a radial kick.
class _Shockwave {
  double radius = 0;
  double strength;

  _Shockwave(this.strength);
}

class _ParticleSystem {
  static const double _waveSpeed = 0.85;
  static const double _waveWidth = 0.13;
  static const double _impulseDamping = 2.6;
  static const int _maxWaves = 4;

  final math.Random _random = math.Random(20260722);
  final List<_Particle> particles = [];
  final List<_Shockwave> waves = [];

  int _lastBeatIndex = -1;
  double _lastElapsedSeconds = -1;

  void _resize(int count) {
    while (particles.length > count) {
      particles.removeLast();
    }
    while (particles.length < count) {
      particles.add(_spawn());
    }
  }

  _Particle _spawn() {
    // Squared distribution biases toward the far field, so the screen has a lot
    // of quiet depth and only a few bright foreground motes.
    final depth = math.pow(_random.nextDouble(), 2).toDouble();
    return _Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      depth: depth,
      baseRadius: 0.9 + _random.nextDouble() * 2.1,
      driftPhaseX: _random.nextDouble() * math.pi * 2,
      driftPhaseY: _random.nextDouble() * math.pi * 2,
      // Deliberately irrational-ish and never equal, so no two particles ever
      // fall into step with each other.
      driftFreqX: 0.05 + _random.nextDouble() * 0.11,
      driftFreqY: 0.04 + _random.nextDouble() * 0.09,
      twinklePhase: _random.nextDouble() * math.pi * 2,
      twinkleRate: 1.4 + _random.nextDouble() * 2.6,
    );
  }

  /// Advances the simulation to [elapsedSeconds].
  void update({
    required double elapsedSeconds,
    required BeatFrame frame,
    required MotionIntensitySpec spec,
  }) {
    _resize(spec.particleCount);

    var dt =
        _lastElapsedSeconds < 0 ? 0.0 : elapsedSeconds - _lastElapsedSeconds;
    _lastElapsedSeconds = elapsedSeconds;
    // Clamp across pauses and dropped frames: integrating a one-second gap
    // would fling every particle off screen at once.
    if (dt <= 0 || dt > 0.1) dt = dt <= 0 ? 0 : 0.1;
    if (dt == 0) return;

    if (frame.hasBeat &&
        frame.beatIndex >= 0 &&
        frame.beatIndex != _lastBeatIndex) {
      _lastBeatIndex = frame.beatIndex;
      if (waves.length >= _maxWaves) waves.removeAt(0);
      waves.add(_Shockwave(frame.isDownbeat ? 1.0 : 0.62));
    } else if (!frame.hasBeat) {
      _lastBeatIndex = -1;
    }

    for (var i = waves.length - 1; i >= 0; i--) {
      final wave = waves[i];
      wave.radius += _waveSpeed * dt;
      wave.strength *= math.exp(-1.9 * dt);
      if (wave.radius > 1.6 || wave.strength < 0.02) waves.removeAt(i);
    }

    // Mid-range energy sets how briskly the field moves; a busy passage stirs
    // it up, a sparse one lets it settle.
    final speed = 0.006 * (0.35 + 0.9 * frame.mid);

    for (final particle in particles) {
      final driftX = math.sin(
            elapsedSeconds * particle.driftFreqX * math.pi * 2 +
                particle.driftPhaseX,
          ) +
          0.55 *
              math.sin(
                elapsedSeconds * particle.driftFreqY * math.pi * 3.1 +
                    particle.driftPhaseY,
              );
      final driftY = math.cos(
            elapsedSeconds * particle.driftFreqY * math.pi * 2 +
                particle.driftPhaseY,
          ) +
          0.55 *
              math.cos(
                elapsedSeconds * particle.driftFreqX * math.pi * 2.7 +
                    particle.driftPhaseX,
              );

      final scale = 0.4 + 0.6 * particle.depth;
      particle.x += (driftX * speed * scale + particle.impulseX) * dt;
      particle.y += (driftY * speed * scale + particle.impulseY) * dt;

      // High-frequency content gives everything a fine shimmer of jitter.
      if (frame.air > 0.01) {
        particle.x += (_random.nextDouble() - 0.5) * 0.0016 * frame.air;
        particle.y += (_random.nextDouble() - 0.5) * 0.0016 * frame.air;
      }

      particle.impulseX *= math.exp(-_impulseDamping * dt);
      particle.impulseY *= math.exp(-_impulseDamping * dt);

      _applyWaves(particle, spec, dt);

      // Toroidal wrap, so the field never thins out at the edges.
      if (particle.x < -0.05) particle.x += 1.1;
      if (particle.x > 1.05) particle.x -= 1.1;
      if (particle.y < -0.05) particle.y += 1.1;
      if (particle.y > 1.05) particle.y -= 1.1;
    }
  }

  void _applyWaves(_Particle particle, MotionIntensitySpec spec, double dt) {
    if (waves.isEmpty) return;

    final dx = particle.x - 0.5;
    final dy = particle.y - 0.44;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1e-4) return;

    for (final wave in waves) {
      final offset = (distance - wave.radius).abs();
      if (offset > _waveWidth) continue;
      // Falls off toward the edges of the wavefront, so particles are nudged as
      // it passes rather than snapping when it arrives.
      final falloff = 1 - offset / _waveWidth;
      final push = wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          0.22 *
          (0.35 + 0.65 * particle.depth);
      particle.impulseX += dx / distance * push * dt * 60;
      particle.impulseY += dy / distance * push * dt * 60;
    }
  }
}

class _ParticlePainter extends CustomPainter {
  final PlayerMotionController controller;
  final _ParticleSystem system;
  final Color accent;

  final Paint _corePaint = Paint()..blendMode = BlendMode.plus;
  final Paint _haloPaint = Paint()..blendMode = BlendMode.plus;

  /// Accent split into two hue-shifted tints. Drawing the same mote in both,
  /// slightly offset, is what reads as light refracting — and it costs two
  /// extra circles rather than a shader or a blur.
  late final Color _warmTint;
  late final Color _coolTint;

  _ParticlePainter({
    required this.controller,
    required this.system,
    required this.accent,
  }) : super(repaint: controller) {
    final hsl = HSLColor.fromColor(accent);
    _warmTint = hsl.withHue((hsl.hue + 22) % 360).toColor();
    _coolTint = hsl.withHue((hsl.hue - 22 + 360) % 360).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final frame = controller.frame;
    final spec = controller.spec;

    system.update(
      elapsedSeconds: controller.elapsed.inMicroseconds / 1e6,
      frame: frame,
      spec: spec,
    );

    // Bass makes the whole field swell outward from the centre and back.
    final swell = 1 + frame.bass * 0.05 + frame.pulse * 0.03;
    final centre = Offset(size.width * 0.5, size.height * 0.44);
    final refraction = frame.pulse;

    for (final particle in system.particles) {
      final base = Offset(particle.x * size.width, particle.y * size.height);
      final position = centre + (base - centre) * swell;

      final twinkle = 0.62 +
          0.38 *
              math.sin(
                controller.elapsed.inMilliseconds /
                        1000 *
                        particle.twinkleRate +
                    particle.twinklePhase,
              ) *
              (0.35 + 0.65 * frame.air);

      final radius = particle.baseRadius *
          (0.45 + 0.55 * particle.depth) *
          (1 + frame.bass * 0.35 + frame.pulse * 0.25);

      final alpha =
          (spec.particleOpacity * (0.3 + 0.7 * particle.depth) * twinkle)
              .clamp(0.0, 1.0);
      if (alpha < 0.01) continue;

      _haloPaint.color = accent.withValues(alpha: alpha * 0.16);
      canvas.drawCircle(position, radius * 2.6, _haloPaint);

      if (refraction > 0.08) {
        final split = radius * 0.9 * refraction;
        _corePaint.color =
            _warmTint.withValues(alpha: alpha * 0.55 * refraction);
        canvas.drawCircle(
            position.translate(split, -split * 0.4), radius, _corePaint);
        _corePaint.color =
            _coolTint.withValues(alpha: alpha * 0.55 * refraction);
        canvas.drawCircle(
            position.translate(-split, split * 0.4), radius, _corePaint);
      }

      _corePaint.color = accent.withValues(alpha: alpha);
      canvas.drawCircle(position, radius, _corePaint);
    }

    _paintShockwaves(canvas, size, centre, spec);
  }

  void _paintShockwaves(
    Canvas canvas,
    Size size,
    Offset centre,
    MotionIntensitySpec spec,
  ) {
    if (system.waves.isEmpty) return;

    final scale = math.max(size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus;

    for (final wave in system.waves) {
      final alpha =
          (wave.strength * spec.particleOpacity * 0.22).clamp(0.0, 1.0);
      if (alpha < 0.01) continue;
      paint
        ..color = accent.withValues(alpha: alpha)
        ..strokeWidth = 1 + 2.5 * wave.strength;
      canvas.drawCircle(centre, wave.radius * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) {
    // Repaint is driven by the controller via `repaint:`; this only matters when
    // the widget itself is rebuilt, e.g. the accent changing between tracks.
    return oldDelegate.accent != accent;
  }

  @override
  bool shouldRebuildSemantics(_ParticlePainter oldDelegate) => false;
}

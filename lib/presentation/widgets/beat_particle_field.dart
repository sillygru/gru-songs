import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'player_motion.dart';

/// Floating particles that drift with the music and breathe on the beat.
///
/// Lives in the player shell rather than any one pane, so the whole screen —
/// lyrics, artwork and queue alike — shares the same field.
///
/// The motion is built to avoid the three things that make particle effects look
/// cheap: perfectly straight travel, every particle doing the same thing at the
/// same time, and a field that quietly drains off screen. Each mote wanders on
/// its own heading and its own pair of out-of-phase sine components, at its own
/// depth, and answers the beat by its own amount — so the field reads as
/// drifting dust rather than confetti on glass.
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
  late final ParticleSystem _system = ParticleSystem();

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
@visibleForTesting
class Particle {
  double x;
  double y;

  /// Displacement along this particle's own radial direction, in normalised
  /// units, and its rate of change.
  ///
  /// A beat pushes this outward and a spring pulls it back to zero. Modelling
  /// the beat as a *displacement that returns* rather than as a velocity is what
  /// keeps the field where it is: an impulse that is never undone gives every
  /// particle a permanent outward drift, and the screen empties.
  double push = 0;
  double pushVelocity = 0;

  /// 0 = far away, 1 = close. Drives size, speed, brightness and how much a
  /// beat moves it — near particles react hard, distant ones barely.
  final double depth;

  /// How strongly this particle answers a beat at all. Without the spread every
  /// mote lunges by the same amount at the same instant, which is what made the
  /// field read as one object rather than many.
  final double response;

  /// Constant heading, on top of the sine wander. Two particles side by side
  /// travel different ways.
  final double headingX;
  final double headingY;

  final double baseRadius;
  final double driftPhaseX;
  final double driftPhaseY;
  final double driftFreqX;
  final double driftFreqY;
  final double twinklePhase;
  final double twinkleRate;

  /// Wall-clock seconds this particle appeared, and how long it takes to reach
  /// full brightness — so the field materialises rather than popping on.
  final double bornAt;
  final double fadeInSeconds;

  Particle({
    required this.x,
    required this.y,
    required this.depth,
    required this.response,
    required this.headingX,
    required this.headingY,
    required this.baseRadius,
    required this.driftPhaseX,
    required this.driftPhaseY,
    required this.driftFreqX,
    required this.driftFreqY,
    required this.twinklePhase,
    required this.twinkleRate,
    required this.bornAt,
    required this.fadeInSeconds,
  });
}

/// An expanding wavefront spawned on a beat, staggering when each particle gets
/// its kick by distance from the centre. Purely a force carrier — nothing draws
/// it.
class _BeatWave {
  double radius = 0;
  double strength;

  _BeatWave(this.strength);
}

@visibleForTesting
class ParticleSystem {
  static const double _waveSpeed = 0.85;
  static const double _waveWidth = 0.13;
  static const int _maxWaves = 4;

  /// Where the field breathes from, in normalised coordinates: roughly where
  /// the artwork sits.
  static const double _centreX = 0.5;
  static const double _centreY = 0.44;

  /// Spring that returns [Particle.push] to rest. Slightly underdamped, so a
  /// beat settles with one soft overshoot instead of creeping back.
  static const double _pushOmega = 2 * math.pi * 2.2;
  static const double _pushDamping = 0.55;
  static const double _maxPush = 0.12;

  /// Integration ceiling. The spring is integrated with semi-implicit Euler,
  /// which needs `omega * dt` comfortably under 2 to stay stable; a hitch longer
  /// than this is already visible, so slowing the simulation across it costs
  /// nothing.
  static const double _maxStepSeconds = 0.05;

  final math.Random _random = math.Random(20260722);
  final List<Particle> particles = [];
  final List<_BeatWave> _waves = [];

  int _lastBeatIndex = -1;
  double _lastElapsedSeconds = -1;
  double _now = 0;

  void _resize(int count) {
    while (particles.length > count) {
      particles.removeLast();
    }
    while (particles.length < count) {
      particles.add(_spawn());
    }
  }

  Particle _spawn() {
    // Squared distribution biases toward the far field, so the screen has a lot
    // of quiet depth and only a few bright foreground motes.
    final depth = math.pow(_random.nextDouble(), 2).toDouble();
    final heading = _random.nextDouble() * math.pi * 2;
    final headingSpeed = 0.002 + _random.nextDouble() * 0.005;
    return Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      depth: depth,
      response: 0.4 + _random.nextDouble() * 0.8,
      headingX: math.cos(heading) * headingSpeed,
      headingY: math.sin(heading) * headingSpeed,
      baseRadius: 0.9 + _random.nextDouble() * 2.1,
      driftPhaseX: _random.nextDouble() * math.pi * 2,
      driftPhaseY: _random.nextDouble() * math.pi * 2,
      // Deliberately irrational-ish and never equal, so no two particles ever
      // fall into step with each other.
      driftFreqX: 0.05 + _random.nextDouble() * 0.11,
      driftFreqY: 0.04 + _random.nextDouble() * 0.09,
      twinklePhase: _random.nextDouble() * math.pi * 2,
      twinkleRate: 1.4 + _random.nextDouble() * 2.6,
      bornAt: _now,
      fadeInSeconds: 0.6 + _random.nextDouble() * 1.4,
    );
  }

  /// Advances the simulation to [elapsedSeconds].
  void update({
    required double elapsedSeconds,
    required BeatFrame frame,
    required MotionIntensitySpec spec,
  }) {
    _now = elapsedSeconds;
    _resize(spec.particleCount);

    var dt =
        _lastElapsedSeconds < 0 ? 0.0 : elapsedSeconds - _lastElapsedSeconds;
    _lastElapsedSeconds = elapsedSeconds;
    if (dt <= 0) return;
    if (dt > _maxStepSeconds) dt = _maxStepSeconds;

    if (frame.hasBeat &&
        frame.beatIndex >= 0 &&
        frame.beatIndex != _lastBeatIndex) {
      _lastBeatIndex = frame.beatIndex;
      if (_waves.length >= _maxWaves) _waves.removeAt(0);
      _waves.add(_BeatWave(frame.isDownbeat ? 1.0 : 0.62));
    } else if (!frame.hasBeat) {
      _lastBeatIndex = -1;
    }

    for (var i = _waves.length - 1; i >= 0; i--) {
      final wave = _waves[i];
      wave.radius += _waveSpeed * dt;
      wave.strength *= math.exp(-1.9 * dt);
      if (wave.radius > 1.6 || wave.strength < 0.02) _waves.removeAt(i);
    }

    // Mid-range energy sets how briskly the field moves; a busy passage stirs
    // it up, a sparse one lets it settle.
    final energy = 0.35 + 0.9 * frame.mid;
    final speed = 0.006 * energy;

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
      particle.x += (driftX * speed + particle.headingX * energy) * scale * dt;
      particle.y += (driftY * speed + particle.headingY * energy) * scale * dt;

      // High-frequency content gives everything a fine shimmer of jitter.
      if (frame.air > 0.01) {
        particle.x += (_random.nextDouble() - 0.5) * 0.0016 * frame.air;
        particle.y += (_random.nextDouble() - 0.5) * 0.0016 * frame.air;
      }

      _stepPush(particle, spec, dt);

      // Toroidal wrap, so the field never thins out at the edges.
      if (particle.x < -0.05) particle.x += 1.1;
      if (particle.x > 1.05) particle.x -= 1.1;
      if (particle.y < -0.05) particle.y += 1.1;
      if (particle.y > 1.05) particle.y -= 1.1;
    }
  }

  /// Advances one particle's radial breath: whatever a passing wavefront adds,
  /// the spring takes back.
  void _stepPush(Particle particle, MotionIntensitySpec spec, double dt) {
    // A small per-particle offset on where the front is felt, so neighbours are
    // reached a moment apart rather than all on the same frame.
    final distance =
        _distanceFromCentre(particle) + (particle.response - 0.8) * 0.05;

    for (final wave in _waves) {
      final offset = (distance - wave.radius).abs();
      if (offset > _waveWidth) continue;
      // Falls off toward the edges of the wavefront, so particles are nudged as
      // it passes rather than snapping when it arrives.
      final falloff = 1 - offset / _waveWidth;
      particle.pushVelocity += wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          particle.response *
          0.22 *
          (0.35 + 0.65 * particle.depth) *
          dt *
          60;
    }

    // Semi-implicit Euler: velocity first, then position, which is what keeps a
    // spring this stiff from winding itself up.
    particle.pushVelocity -= (_pushOmega * _pushOmega * particle.push +
            2 * _pushDamping * _pushOmega * particle.pushVelocity) *
        dt;
    particle.push =
        (particle.push + particle.pushVelocity * dt).clamp(-_maxPush, _maxPush);
  }

  double _distanceFromCentre(Particle particle) {
    final dx = particle.x - _centreX;
    final dy = particle.y - _centreY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Where a particle is actually drawn: its drifting position, displaced along
  /// its own radius by the beat breath.
  Offset displacedPosition(Particle particle) {
    final dx = particle.x - _centreX;
    final dy = particle.y - _centreY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1e-4) return Offset(particle.x, particle.y);
    return Offset(
      particle.x + dx / distance * particle.push,
      particle.y + dy / distance * particle.push,
    );
  }

  /// 0..1 fade for a freshly spawned particle.
  double fadeOf(Particle particle) {
    final age = _now - particle.bornAt;
    if (age >= particle.fadeInSeconds) return 1;
    return (age / particle.fadeInSeconds).clamp(0.0, 1.0);
  }
}

class _ParticlePainter extends CustomPainter {
  final PlayerMotionController controller;
  final ParticleSystem system;
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

    final refraction = frame.pulse;

    for (final particle in system.particles) {
      final normalised = system.displacedPosition(particle);
      // A whisper of bass swell on top, weighted by depth so it is not one
      // uniform zoom — the beat response itself lives in the particle.
      final swell = 1 + frame.bass * 0.02 * (0.3 + 0.7 * particle.depth);
      final centre = Offset(size.width * 0.5, size.height * 0.44);
      final base =
          Offset(normalised.dx * size.width, normalised.dy * size.height);
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

      final alpha = (spec.particleOpacity *
              (0.3 + 0.7 * particle.depth) *
              twinkle *
              system.fadeOf(particle))
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

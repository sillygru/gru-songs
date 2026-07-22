import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'player_motion.dart';

/// Floating motes that wander the player screen and glow with the music.
///
/// Lives in the player shell rather than any one pane, so the whole screen —
/// lyrics, artwork and queue alike — shares the same field.
///
/// The field is built around one rule: **it has to actually go somewhere.** An
/// earlier version drove position from a sinusoidal *velocity*, which integrates
/// to an oscillation a couple of percent of the screen wide, and layered
/// per-frame white noise on top — so the motes buzzed in place instead of
/// travelling. Here each mote carries a real velocity, steers it toward a smooth
/// spatial flow field, and crosses the screen in something like fifteen seconds.
///
/// On top of that travel each mote lives its own life: its own slow glow cycle,
/// its own lifetime, and its own answer to the beat. Nothing is driven by a
/// global per-frame term, because a field where every mote flares on the same
/// frame reads as one object blinking rather than many things listening.
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

  /// Travel velocity in normalised units per second. Steered toward the flow
  /// field rather than set from it, so paths curve instead of kinking.
  double vx = 0;
  double vy = 0;

  /// Displacement along this particle's own radial direction, in normalised
  /// units, and its rate of change.
  ///
  /// A beat pushes this outward and a spring pulls it back to zero. Modelling
  /// the beat as a *displacement that returns* rather than as a velocity is what
  /// keeps the field where it is: an impulse that is never undone gives every
  /// particle a permanent outward drift, and the screen empties.
  double push = 0;
  double pushVelocity = 0;

  /// Angular velocity about the field centre, in radians per second, decaying
  /// with drag.
  ///
  /// This is where the *visible* beat travel comes from. A rotation can never
  /// drain the field the way an outward impulse can, so it can be large enough
  /// to see without any risk of the screen slowly emptying.
  double swirlVelocity = 0;

  /// 0..1 flare left over from the last beat this mote answered, decaying on
  /// its own [excitationTau]. Size, brightness and the colour split all read
  /// from here rather than from the global frame — that is what keeps the field
  /// from strobing in unison.
  double excitation = 0;

  /// 0 = far away, 1 = close. Drives size, speed, brightness and how much a
  /// beat moves it — near particles react hard, distant ones barely.
  final double depth;

  /// How strongly this particle answers a beat at all. Without the spread every
  /// mote lunges by the same amount at the same instant, which is what made the
  /// field read as one object rather than many.
  final double response;

  /// A wave weaker than this passes straight through. Quiet offbeats therefore
  /// stir a handful of motes and downbeats stir all of them, so the field reads
  /// as listening rather than as being triggered.
  final double beatThreshold;

  /// Which way this mote leans when a beat spins the field, and by how much.
  /// Signed per particle so a beat raises eddies rather than turning the whole
  /// field like a wheel.
  final double swirlBias;

  /// Travel speed at full energy, normalised units per second.
  final double baseSpeed;

  /// Constant heading bias on top of the flow, so two motes caught in the same
  /// current still separate.
  final double headingX;
  final double headingY;

  /// How quickly velocity converges on the flow. Longer means heavier and more
  /// sweeping; shorter means darting.
  final double steerTau;

  /// How long a beat flare takes to fade.
  final double excitationTau;

  final double baseRadius;

  /// Slow independent brightness cycle — the firefly part.
  final double glowRate;
  final double glowPhase;

  final double twinklePhase;
  final double twinkleRate;
  final double wobblePhase;

  /// Direction the chromatic split is thrown on a flare, in radians. Per
  /// particle, so a flare is not the same fixed diagonal smear everywhere.
  final double splitAngle;

  /// Wall-clock seconds this particle appeared, how long it takes to reach full
  /// brightness, how long it lives and how long it takes to leave — so the
  /// field materialises, renews itself and never pops.
  final double bornAt;
  final double fadeInSeconds;
  final double lifeSeconds;
  final double fadeOutSeconds;

  Particle({
    required this.x,
    required this.y,
    required this.depth,
    required this.response,
    required this.beatThreshold,
    required this.swirlBias,
    required this.baseSpeed,
    required this.headingX,
    required this.headingY,
    required this.steerTau,
    required this.excitationTau,
    required this.baseRadius,
    required this.glowRate,
    required this.glowPhase,
    required this.twinklePhase,
    required this.twinkleRate,
    required this.wobblePhase,
    required this.splitAngle,
    required this.bornAt,
    required this.fadeInSeconds,
    required this.lifeSeconds,
    required this.fadeOutSeconds,
  });
}

/// An expanding wavefront spawned on a beat, staggering when each particle gets
/// its kick by distance from the centre. Purely a force carrier — nothing draws
/// it.
class _BeatWave {
  double radius = 0;

  /// Decays as the front spreads, so the far field is stirred more gently than
  /// the near field.
  double strength;

  /// The beat's strength at the moment it landed, held constant. Recruitment
  /// reads this rather than [strength], so which motes answer a beat is decided
  /// by how hard the beat hit and not by how far the front has already gone.
  final double power;

  /// Which way this beat turns the field.
  ///
  /// Hashed from the beat index rather than alternated with it: downbeats fall
  /// on every fourth beat and so always share a parity, which means a strict
  /// alternation hands the strongest beat of every bar to the same direction.
  /// The field then creeps around one way and reads as a slow wheel. A hash
  /// breaks that correlation while staying deterministic, so a track turns the
  /// same way every play.
  final double swirl;

  _BeatWave({
    required this.strength,
    required this.power,
    required this.swirl,
  });
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

  /// Drag on [Particle.swirlVelocity], and a ceiling so a run of beats landing
  /// the same way cannot wind a mote up into a spin.
  ///
  /// The time constant is deliberately shorter than a beat at any danceable
  /// tempo, so each beat's turn has mostly bled off before the next one lands
  /// and the rotation stays a nudge rather than something that accumulates.
  static const double _swirlTau = 0.40;
  static const double _maxSwirl = 0.45;

  /// How much of the travel comes from the shared flow versus each mote's own
  /// heading.
  static const double _flowGain = 0.85;

  /// Where a mote is wrapped back around, and the band over which it fades out
  /// on the way there. Equal by construction, so a mote is invisible by the
  /// time it wraps.
  static const double _wrapMargin = 0.08;

  /// Peak of the smooth positional shimmer at full high-frequency energy.
  static const double _wobbleAmplitude = 0.0022;

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
  double _air = 0;

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
    final headingWeight = 0.25 + _random.nextDouble() * 0.35;
    return Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      depth: depth,
      response: 0.4 + _random.nextDouble() * 0.8,
      beatThreshold: 0.15 + _random.nextDouble() * 0.75,
      swirlBias: (_random.nextBool() ? 1.0 : -1.0) *
          (0.45 + _random.nextDouble() * 0.85),
      // Near motes travel faster than far ones: the same parallax that makes
      // depth read as depth rather than as size.
      baseSpeed: (0.026 + 0.050 * depth) * (0.8 + _random.nextDouble() * 0.4),
      headingX: math.cos(heading) * headingWeight,
      headingY: math.sin(heading) * headingWeight,
      steerTau: 0.6 + _random.nextDouble() * 1.0,
      excitationTau: 0.18 + _random.nextDouble() * 0.27,
      baseRadius: 0.9 + _random.nextDouble() * 2.1,
      glowRate: 0.12 + _random.nextDouble() * 0.33,
      glowPhase: _random.nextDouble() * math.pi * 2,
      twinklePhase: _random.nextDouble() * math.pi * 2,
      twinkleRate: 1.4 + _random.nextDouble() * 2.6,
      wobblePhase: _random.nextDouble() * math.pi * 2,
      splitAngle: _random.nextDouble() * math.pi * 2,
      bornAt: _now,
      fadeInSeconds: 0.6 + _random.nextDouble() * 1.4,
      // Spread wide enough that the field renews a mote at a time instead of
      // turning over in one visible wave.
      lifeSeconds: 14 + _random.nextDouble() * 26,
      fadeOutSeconds: 1.8 + _random.nextDouble() * 1.4,
    );
  }

  /// Recycles a mote in place, keeping the list stable while giving it an
  /// entirely new character and somewhere new to be.
  void _respawn(int index) {
    particles[index] = _spawn();
  }

  /// Two-scale pseudo-curl flow. Spatially varying and slowly turning, so
  /// neighbouring motes share a local current for a while and then diverge —
  /// eddies rather than parallel lanes. Scaled to roughly unit magnitude.
  /// Divided by the sum's *typical* magnitude rather than its worst case: three
  /// sines at these amplitudes almost never peak together, so normalising by
  /// 1.5 would leave the field drifting at less than half the intended speed.
  static double _flowX(double x, double y, double t) =>
      (math.sin(y * 5.1 + t * 0.29) * 0.7 +
          math.sin(y * 2.3 - x * 1.7 + t * 0.17) * 0.5 +
          math.sin(x * 3.7 + t * 0.11) * 0.3) /
      0.8;

  static double _flowY(double x, double y, double t) =>
      (math.cos(x * 4.6 - t * 0.23) * 0.7 +
          math.cos(x * 2.9 + y * 1.9 - t * 0.13) * 0.5 +
          math.cos(y * 3.1 - t * 0.19) * 0.3) /
      0.8;

  /// Advances the simulation to [elapsedSeconds].
  void update({
    required double elapsedSeconds,
    required BeatFrame frame,
    required MotionIntensitySpec spec,
  }) {
    _now = elapsedSeconds;
    _air = frame.air;
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
      final power = frame.strength;
      _waves.add(_BeatWave(
        strength: power,
        power: power,
        swirl: _beatSpin(frame.beatIndex),
      ));
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
    final energy = (0.75 + 0.5 * frame.mid) * spec.particleDrift;
    final swirlDecay = math.exp(-dt / _swirlTau);

    for (var i = 0; i < particles.length; i++) {
      final particle = particles[i];

      if (_now - particle.bornAt >= particle.lifeSeconds) {
        _respawn(i);
        continue;
      }

      final flowX = _flowX(particle.x, particle.y, elapsedSeconds);
      final flowY = _flowY(particle.x, particle.y, elapsedSeconds);
      final speed = particle.baseSpeed * energy;
      final targetVx = (flowX * _flowGain + particle.headingX) * speed;
      final targetVy = (flowY * _flowGain + particle.headingY) * speed;

      // Exponential steering rather than a fixed lerp, so the feel does not
      // change with frame rate — and `dt` is clamped above, so it would.
      final blend = 1 - math.exp(-dt / particle.steerTau);
      particle.vx += (targetVx - particle.vx) * blend;
      particle.vy += (targetVy - particle.vy) * blend;

      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;

      _stepBeatResponse(particle, spec, dt, swirlDecay);

      // Toroidal wrap, so the field never thins out at the edges. The edge fade
      // has already taken the mote to zero alpha by the time it gets here.
      if (particle.x < -_wrapMargin) particle.x += 1 + 2 * _wrapMargin;
      if (particle.x > 1 + _wrapMargin) particle.x -= 1 + 2 * _wrapMargin;
      if (particle.y < -_wrapMargin) particle.y += 1 + 2 * _wrapMargin;
      if (particle.y > 1 + _wrapMargin) particle.y -= 1 + 2 * _wrapMargin;
    }
  }

  /// Advances one particle's answer to the beat: the radial breath a spring
  /// takes back, the rotation drag takes back, and the flare that fades.
  void _stepBeatResponse(
    Particle particle,
    MotionIntensitySpec spec,
    double dt,
    double swirlDecay,
  ) {
    // A small per-particle offset on where the front is felt, so neighbours are
    // reached a moment apart rather than all on the same frame.
    final distance =
        _distanceFromCentre(particle) + (particle.response - 0.8) * 0.05;

    for (final wave in _waves) {
      // Waves too weak for this mote pass straight through it.
      if (wave.power < particle.beatThreshold) continue;

      final offset = (distance - wave.radius).abs();
      if (offset > _waveWidth) continue;
      // Falls off toward the edges of the wavefront, so particles are nudged as
      // it passes rather than snapping when it arrives.
      final falloff = 1 - offset / _waveWidth;
      // `dt * 60` normalises the accumulation to a per-60fps-frame impulse, so
      // the total a mote picks up crossing the front does not depend on the
      // frame rate.
      final impulse = wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          particle.response *
          (0.35 + 0.65 * particle.depth) *
          dt *
          60;

      particle.pushVelocity += impulse * 0.22;
      particle.excitation = math.min(1.0, particle.excitation + impulse * 0.30);

      // The turn deliberately does not carry `response`. Stacking every spread
      // that already shapes the push — response, depth and bias together — puts
      // a 25x range on the rotation, so the liveliest motes saturate the cap
      // into a constant spin while typical ones turn by a fraction of a degree.
      // Depth and bias alone leave enough variety without either extreme.
      final turn = wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          (0.5 + 0.5 * particle.depth) *
          dt *
          60;
      particle.swirlVelocity += turn * 0.04 * particle.swirlBias * wave.swirl;
    }

    // Semi-implicit Euler: velocity first, then position, which is what keeps a
    // spring this stiff from winding itself up.
    particle.pushVelocity -= (_pushOmega * _pushOmega * particle.push +
            2 * _pushDamping * _pushOmega * particle.pushVelocity) *
        dt;
    particle.push =
        (particle.push + particle.pushVelocity * dt).clamp(-_maxPush, _maxPush);

    particle.excitation *= math.exp(-dt / particle.excitationTau);

    particle.swirlVelocity =
        (particle.swirlVelocity * swirlDecay).clamp(-_maxSwirl, _maxSwirl);
    if (particle.swirlVelocity.abs() > 1e-4) {
      // Rotating the position itself, rather than offsetting at paint time, so
      // the beat genuinely carries the mote somewhere new instead of returning
      // it to where it started.
      final angle = particle.swirlVelocity * dt;
      final dx = particle.x - _centreX;
      final dy = particle.y - _centreY;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      particle.x = _centreX + dx * cos - dy * sin;
      particle.y = _centreY + dx * sin + dy * cos;
    }
  }

  /// A stable ±1 for a beat index. Cheap integer hash rather than a Random, so
  /// the same track spins the same way on every play without carrying state.
  static double _beatSpin(int index) {
    var hash = index * 0x27d4eb2d;
    hash ^= hash >> 15;
    hash *= 0x85ebca6b;
    hash ^= hash >> 13;
    return (hash & 1) == 0 ? 1.0 : -1.0;
  }

  double _distanceFromCentre(Particle particle) {
    final dx = particle.x - _centreX;
    final dy = particle.y - _centreY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Where a particle is actually drawn: its travelling position, displaced
  /// along its own radius by the beat breath and shimmering on its own phase.
  Offset displacedPosition(Particle particle) {
    final dx = particle.x - _centreX;
    final dy = particle.y - _centreY;
    final distance = math.sqrt(dx * dx + dy * dy);

    var x = particle.x;
    var y = particle.y;
    if (distance >= 1e-4) {
      x += dx / distance * particle.push;
      y += dy / distance * particle.push;
    }

    // Smooth shimmer on the mote's own phase, in place of the per-frame white
    // noise this used to add to the simulation. That noise was uncorrelated
    // frame to frame, which at 60fps is a 60Hz buzz — the fastest thing on
    // screen, and so the only motion the eye actually read.
    if (_air > 0.01) {
      final wobble = _wobbleAmplitude * _air;
      x += math.sin(_now * particle.twinkleRate * 1.7 + particle.wobblePhase) *
          wobble;
      y += math.cos(_now * particle.twinkleRate * 1.3 + particle.twinklePhase) *
          wobble;
    }
    return Offset(x, y);
  }

  /// 0..1 birth-and-death fade.
  double fadeOf(Particle particle) {
    final age = _now - particle.bornAt;
    if (age < particle.fadeInSeconds) {
      return (age / particle.fadeInSeconds).clamp(0.0, 1.0);
    }
    final remaining = particle.lifeSeconds - age;
    if (remaining < particle.fadeOutSeconds) {
      return (remaining / particle.fadeOutSeconds).clamp(0.0, 1.0);
    }
    return 1;
  }

  /// 0..1 fade as a mote leaves the screen, reaching zero exactly at the wrap
  /// point so the wrap is never seen.
  double edgeFadeOf(Particle particle) {
    final outX =
        particle.x < 0 ? -particle.x : (particle.x > 1 ? particle.x - 1 : 0.0);
    final outY =
        particle.y < 0 ? -particle.y : (particle.y > 1 ? particle.y - 1 : 0.0);
    final out = math.max(outX, outY);
    if (out <= 0) return 1;
    return (1 - out / _wrapMargin).clamp(0.0, 1.0);
  }

  /// Slow independent brightness cycle — what makes a mote read as a firefly
  /// rather than a dot at a fixed opacity.
  double glowOf(Particle particle) {
    return 0.55 +
        0.45 *
            math.sin(
              _now * particle.glowRate * 2 * math.pi + particle.glowPhase,
            );
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
    final seconds = controller.elapsed.inMicroseconds / 1e6;

    system.update(
      elapsedSeconds: seconds,
      frame: frame,
      spec: spec,
    );

    // Shimmer depth, not shimmer itself: high-frequency content decides how
    // hard each mote twinkles on its own phase, rather than twinkling them all
    // together.
    final shimmer = 0.15 + 0.35 * frame.air;

    for (final particle in system.particles) {
      final fade = system.fadeOf(particle) * system.edgeFadeOf(particle);
      if (fade < 0.01) continue;

      final normalised = system.displacedPosition(particle);
      final position =
          Offset(normalised.dx * size.width, normalised.dy * size.height);

      // Everything beat-driven below reads from this mote's own flare, which
      // decays on its own time constant. Driving size and brightness from the
      // global pulse instead is what made the whole field blink as one.
      final flare = particle.excitation;

      final twinkle = 1 -
          shimmer +
          shimmer *
              (0.5 +
                  0.5 *
                      math.sin(
                        seconds * particle.twinkleRate + particle.twinklePhase,
                      ));

      final radius = particle.baseRadius *
          (0.45 + 0.55 * particle.depth) *
          (1 + flare * 0.5);

      final alpha = (spec.particleOpacity *
              (0.3 + 0.7 * particle.depth) *
              system.glowOf(particle) *
              twinkle *
              (1 + flare * 0.9) *
              fade)
          .clamp(0.0, 1.0);
      if (alpha < 0.01) continue;

      _haloPaint.color = accent.withValues(alpha: alpha * 0.16);
      canvas.drawCircle(position, radius * 2.6, _haloPaint);

      if (flare > 0.08) {
        // Thrown along this mote's own axis, so a flare is a scatter of little
        // prisms rather than one diagonal smear repeated across the screen.
        final split = radius * 0.9 * flare;
        final dx = math.cos(particle.splitAngle) * split;
        final dy = math.sin(particle.splitAngle) * split;
        _corePaint.color = _warmTint.withValues(alpha: alpha * 0.55 * flare);
        canvas.drawCircle(position.translate(dx, dy), radius, _corePaint);
        _corePaint.color = _coolTint.withValues(alpha: alpha * 0.55 * flare);
        canvas.drawCircle(position.translate(-dx, -dy), radius, _corePaint);
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

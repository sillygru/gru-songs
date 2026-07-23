import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'player_motion.dart';

/// Floating motes that wander the player screen and glow with the music.
///
/// Lives in the player shell rather than any one pane, so the whole screen —
/// lyrics, artwork and queue alike — shares the same field.
///
/// The field is built around one rule: **the music has to be what moves them.**
///
/// Two earlier versions missed that in different ways. The first drove position
/// from a sinusoidal *velocity*, which integrates to an oscillation a couple of
/// percent of the screen wide, so the motes buzzed in place. The second gave
/// them real travel — but drove it entirely from a wall-clock flow field, and
/// left the beat with only forces that undo themselves: a radial spring that
/// returns to rest by construction, and a rotation small enough to be
/// sub-perceptual. The motes wandered convincingly and shivered on the beat
/// without ever being *carried* by it.
///
/// So travel here is split in two. Ambient velocity steers toward a slow
/// divergence-free flow — the wandering — while a separate [Particle.surgeX] /
/// [Particle.surgeY] is kicked along each mote's own heading when a beat reaches
/// it and decays over a fraction of a beat. The surge leaves real displacement
/// behind, roughly `Δv · τ` per beat, so the field advances in time with the
/// music and coasts between. Because the kick follows the mote's heading rather
/// than pointing outward, it cannot drain the screen the way a radial impulse
/// does — see [ParticleSystem._stepBeatResponse].
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
///
/// Velocities, unlike positions, are in *visual* units — screen widths per
/// second on both axes — so a heading means the same thing horizontally and
/// vertically. [ParticleSystem.update] converts to normalised units at the
/// integration step. Without that, the same number moves a mote more than twice
/// as far vertically as horizontally on a phone, and every direction in the
/// simulation is quietly a different direction on screen.
@visibleForTesting
class Particle {
  double x;
  double y;

  /// Ambient travel velocity. Steered toward the flow field rather than set from
  /// it, so paths curve instead of kinking.
  double vx = 0;
  double vy = 0;

  /// Beat-driven travel velocity, added to the ambient one and decaying on
  /// [ParticleSystem._surgeTau] with no steering of its own.
  ///
  /// This is where the visible beat travel lives. It decays to zero, so it never
  /// accumulates into a runaway — but unlike a spring it is never pulled *back*,
  /// so each beat leaves roughly `Δv · τ` of permanent displacement behind. That
  /// is the difference between a field that shivers on the beat and one the beat
  /// actually carries.
  double surgeX = 0;
  double surgeY = 0;

  /// Displacement along this particle's own radial direction, in normalised
  /// units, and its rate of change.
  ///
  /// A beat pushes this outward and a spring pulls it back to zero. Modelling
  /// the beat as a *displacement that returns* rather than as a velocity is what
  /// keeps the field where it is: an impulse that is never undone gives every
  /// particle a permanent outward drift, and the screen empties.
  double push = 0;
  double pushVelocity = 0;

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

  /// Which way this mote leans when a beat turns it, and by how much. Signed per
  /// particle so a beat raises eddies rather than turning the whole field like a
  /// wheel.
  final double swirlBias;

  /// How far off its own heading this mote is thrown when a beat surges it,
  /// in radians. Signed with [swirlBias], so a mote leans the same way it turns.
  final double swerveAngle;

  /// Travel speed at full energy, in visual units per second.
  final double baseSpeed;

  /// Heading bias on top of the flow, so two motes caught in the same current
  /// still separate.
  ///
  /// Rotated by beats rather than fixed, so a mote's long-run direction is
  /// something the music decided. It is deliberately weak: a strong constant
  /// heading is ballistic translation, and it was most of why motes used to
  /// march off the edge of the screen instead of wandering a region of it.
  double headingX;
  double headingY;

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
    required this.swerveAngle,
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
  /// How fast a beat's wavefront crosses the field, and how thick it is.
  ///
  /// The speed is set by a hard constraint: the front has to reach the far edge
  /// well inside one beat. The field is about 0.6 across in these units, so at
  /// the 0.85 this used to be, arrival times spanned ~0.7s — longer than a beat
  /// at 120 BPM. Every mote still surged on a beat, but each at a different
  /// phase, and the field as a whole averaged out to no beat-locked motion at
  /// all. At this speed the front reaches the far edge in ~0.1s and the travel
  /// it starts has resolved within ~0.3s, while the sweep is still staggered
  /// enough to read as a ripple rather than as everything moving at once.
  static const double _waveSpeed = 6.5;
  static const double _waveWidth = 0.13;
  static const int _maxWaves = 4;

  /// Normalises the impulse a mote accumulates while a front passes over it.
  ///
  /// The raw per-frame sum is proportional to `_waveWidth / _waveSpeed` — the
  /// time the front takes to cross — so without this, retuning the geometry
  /// silently retunes how hard beats hit. With it, a mote crossing a
  /// full-strength front accumulates exactly 1.0 before the per-particle terms,
  /// which is the basis every gain below is expressed against.
  static const double _frontGain = 3 * _waveSpeed / (2 * _waveWidth);

  /// Where the field breathes from, in normalised coordinates: roughly where
  /// the artwork sits.
  static const double _centreX = 0.5;
  static const double _centreY = 0.44;

  /// Spring that returns [Particle.push] to rest. Slightly underdamped, so a
  /// beat settles with one soft overshoot instead of creeping back.
  static const double _pushOmega = 2 * math.pi * 2.2;
  static const double _pushDamping = 0.55;
  static const double _maxPush = 0.12;

  /// How long a beat's kick to [Particle.surgeX] takes to bleed off, and the
  /// ceiling on it.
  ///
  /// Shorter than a beat at any danceable tempo, so each beat's travel has
  /// mostly resolved before the next lands — the field surges and coasts rather
  /// than riding a raised plateau. Net displacement per beat is roughly
  /// `Δv · _surgeTau`, which is what [_surgeGain] is set against.
  static const double _surgeTau = 0.18;
  static const double _maxSurge = 0.8;

  /// Converts the impulse a mote picks up crossing a wavefront into surge
  /// velocity, and into radians of heading change.
  ///
  /// Both are set from a target rather than by feel: at `bold`, a full-strength
  /// beat moves a mote about 4.5% of the screen width (`Δv · _surgeTau`) and
  /// turns it by roughly a quarter radian.
  /// `test/particle_travel_metrics_test.dart` measures the result of both, so
  /// retuning them means moving a number the tests already report.
  static const double _surgeGain = 0.25;
  static const double _swerveGain = 0.25;

  /// The radial breath and the flare, against the same unit basis.
  static const double _pushGain = 1.0;
  static const double _flareGain = 1.8;

  /// How much of the travel comes from the shared flow versus each mote's own
  /// heading.
  static const double _flowGain = 0.85;

  /// The band at each edge where a mote is nudged back inward, and how hard.
  ///
  /// Deliberately soft. Motes are *allowed* to leave and wrap — a field that
  /// never crosses an edge reads as trapped in a box — but with nothing pulling
  /// back, a fifth of the field was off screen at any moment. This curves most
  /// paths around before they get there without ever forbidding the crossing;
  /// a mote riding a strong surge still sails straight out.
  static const double _edgeBand = 0.12;
  static const double _edgeBias = 0.05;

  /// Where a mote is wrapped back around, and how far *inside* the border its
  /// fade begins.
  ///
  /// The fade used to start only once the mote was already outside `0..1`, so
  /// the whole of it happened where nobody could see it: motes held full alpha
  /// to the border and then vanished. Starting inside means the exit is a fade
  /// rather than a clip, and the margin past the border only has to cover what
  /// is left.
  static const double _wrapMargin = 0.04;
  static const double _edgeFadeInset = 0.03;

  /// Peak of the smooth positional shimmer at full high-frequency energy.
  static const double _wobbleAmplitude = 0.0022;

  /// Integration ceiling. The spring is integrated with semi-implicit Euler,
  /// which needs `omega * dt` comfortably under 2 to stay stable; a hitch longer
  /// than this is already visible, so slowing the simulation across it costs
  /// nothing.
  static const double _maxStepSeconds = 0.05;

  /// How fast the flow field itself evolves: a floor so it never freezes solid,
  /// a term that rises with the music's energy, and a kick on every beat.
  static const double _flowIdleRate = 0.40;
  static const double _flowEnergyRate = 1.10;
  static const double _flowBeatRate = 3.00;
  static const double _flowKickTau = 0.25;

  final math.Random _random = math.Random(20260722);
  final List<Particle> particles = [];
  final List<_BeatWave> _waves = [];

  int _lastBeatIndex = -1;
  double _lastElapsedSeconds = -1;
  double _now = 0;
  double _air = 0;

  /// Screen width over height. Positions stay normalised `0..1` on both axes,
  /// but velocities are isotropic, so the conversion happens here.
  double _aspect = 1;

  /// The flow field's own clock, advancing with the music rather than with the
  /// wall.
  ///
  /// Kept separate from [_now], which still drives the glow, twinkle and
  /// lifetimes: those are the field's idle life and have to keep running at a
  /// constant rate. This one lurches on beats and nearly stalls in a quiet
  /// passage, so the whole current re-aims in time with the track and
  /// neighbouring motes shift together.
  double _flowTime = 0;
  double _beatKick = 0;

  /// Output of the last [_sampleFlow]. Written rather than returned: this runs
  /// once per particle per frame, and a record would allocate on every call.
  double _flowVx = 0;
  double _flowVy = 0;

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
    // Weak by design — see [Particle.headingX]. The eddies do the travelling;
    // this only keeps two motes in the same current from tracking each other.
    final headingWeight = 0.10 + _random.nextDouble() * 0.15;
    final swirlBias = (_random.nextBool() ? 1.0 : -1.0) *
        (0.45 + _random.nextDouble() * 0.85);
    return Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      depth: depth,
      response: 0.4 + _random.nextDouble() * 0.8,
      beatThreshold: 0.15 + _random.nextDouble() * 0.75,
      swirlBias: swirlBias,
      swerveAngle: swirlBias.sign * (0.25 + _random.nextDouble() * 0.5),
      // Near motes travel faster than far ones: the same parallax that makes
      // depth read as depth rather than as size.
      baseSpeed: (0.021 + 0.040 * depth) * (0.8 + _random.nextDouble() * 0.4),
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

  /// Two-octave flow field, written into [_flowVx] / [_flowVy].
  ///
  /// This is the **curl of a stream function** `ψ = Σ aᵢ·sin(kᵢx)·cos(lᵢy)`
  /// rather than an arbitrary pair of sine sums, and that is the whole point:
  ///
  ///     flowX =  ∂ψ/∂y     flowY = -∂ψ/∂x
  ///
  /// A field built that way is divergence-free, so it has no sources and no
  /// sinks and advecting motes through it preserves their density exactly. The
  /// previous version summed sines independently per axis, which does have
  /// sources and sinks — the field pooled into bands and left the rest of the
  /// screen empty, measurably so.
  ///
  /// It costs eight transcendentals per sample against the previous six — both
  /// components share the four per octave — which is the price of the guarantee,
  /// not a saving. At 58 motes that is ~28k calls a second, well inside budget
  /// for a layer that already draws two to four blended circles per mote.
  ///
  /// [yv] is the vertical coordinate in the same units as [x], so the eddies are
  /// round on screen instead of stretched. The phases drift with [t] — a static
  /// stream function has closed streamlines, and motes would orbit one eddy
  /// forever and stop travelling at all.
  void _sampleFlow(double x, double yv, double t) {
    const k1 = 5.5, l1 = 4.5, a1 = 1.0;
    const k2 = 10.1, l2 = 8.3, a2 = 0.38;

    final u1 = k1 * x + t * 0.31;
    final v1 = l1 * yv - t * 0.23;
    final u2 = k2 * x - t * 0.19;
    final v2 = l2 * yv + t * 0.27;

    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinV1 = math.sin(v1), cosV1 = math.cos(v1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);
    final sinV2 = math.sin(v2), cosV2 = math.cos(v2);

    // Normalised by the sum's *typical* magnitude rather than its worst case:
    // the octaves almost never peak together, so dividing by the maximum would
    // leave the field drifting at a fraction of the intended speed.
    const norm = 1 / 5.6;
    _flowVx = -(a1 * l1 * sinU1 * sinV1 + a2 * l2 * sinU2 * sinV2) * norm;
    _flowVy = -(a1 * k1 * cosU1 * cosV1 + a2 * k2 * cosU2 * cosV2) * norm;
  }

  /// Advances the simulation to [elapsedSeconds].
  ///
  /// [aspect] is the painted box's width over its height. It defaults to square
  /// so a caller that does not care — or has no size yet — still gets a sane
  /// simulation.
  void update({
    required double elapsedSeconds,
    required BeatFrame frame,
    required MotionIntensitySpec spec,
    double aspect = 1,
  }) {
    _now = elapsedSeconds;
    _air = frame.air;
    _aspect = aspect <= 0 ? 1 : aspect;
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
      // Shoves the flow field's own clock forward, so the current re-aims on the
      // beat rather than only the motes riding it.
      _beatKick = math.max(_beatKick, power);
    } else if (!frame.hasBeat) {
      _lastBeatIndex = -1;
    }

    for (var i = _waves.length - 1; i >= 0; i--) {
      final wave = _waves[i];
      wave.radius += _waveSpeed * dt;
      wave.strength *= math.exp(-1.9 * dt);
      if (wave.radius > 1.6 || wave.strength < 0.02) _waves.removeAt(i);
    }

    // Band energy sets how briskly the field moves; a busy passage stirs it up,
    // a sparse one lets it settle. Wider than it was, so the difference between
    // a breakdown and a drop is something the eye can actually read.
    final energy =
        (0.30 + 0.80 * frame.mid + 0.30 * frame.bass) * spec.particleDrift;
    final surgeDecay = math.exp(-dt / _surgeTau);

    _beatKick *= math.exp(-dt / _flowKickTau);
    _flowTime += dt *
        (_flowIdleRate + _flowEnergyRate * energy + _flowBeatRate * _beatKick);

    // 1 normalised unit of y is one screen height, i.e. `1 / aspect` widths, so
    // this is what turns an isotropic velocity back into normalised travel.
    final yScale = _aspect;
    final invAspect = 1 / _aspect;

    for (var i = 0; i < particles.length; i++) {
      final particle = particles[i];

      if (_now - particle.bornAt >= particle.lifeSeconds) {
        _respawn(i);
        continue;
      }

      _sampleFlow(particle.x, particle.y * invAspect, _flowTime);
      final speed = particle.baseSpeed * energy;
      final targetVx = (_flowVx * _flowGain + particle.headingX) * speed;
      final targetVy = (_flowVy * _flowGain + particle.headingY) * speed;

      // Exponential steering rather than a fixed lerp, so the feel does not
      // change with frame rate — and `dt` is clamped above, so it would.
      final blend = 1 - math.exp(-dt / particle.steerTau);
      particle.vx += (targetVx - particle.vx) * blend;
      particle.vy += (targetVy - particle.vy) * blend;

      _applyEdgeBias(particle, dt, invAspect);

      particle.x += (particle.vx + particle.surgeX) * dt;
      particle.y += (particle.vy + particle.surgeY) * yScale * dt;

      _stepBeatResponse(particle, spec, dt, surgeDecay);

      // Toroidal wrap, so the field never thins out at the edges. The edge fade
      // has already taken the mote to zero alpha by the time it gets here.
      if (particle.x < -_wrapMargin) particle.x += 1 + 2 * _wrapMargin;
      if (particle.x > 1 + _wrapMargin) particle.x -= 1 + 2 * _wrapMargin;
      if (particle.y < -_wrapMargin) particle.y += 1 + 2 * _wrapMargin;
      if (particle.y > 1 + _wrapMargin) particle.y -= 1 + 2 * _wrapMargin;
    }
  }

  /// Leans a mote's ambient velocity back toward the middle once it is inside
  /// [_edgeBand] of an edge, in proportion to how far in it has gone.
  ///
  /// Acts on the ambient velocity only, never on the surge, and never clamps the
  /// position: a mote can still leave, and one carried out by a strong beat
  /// will. It just makes leaving something that happens occasionally rather than
  /// a fifth of the time.
  void _applyEdgeBias(Particle particle, double dt, double invAspect) {
    final push = _edgeBias * dt;

    if (particle.x < _edgeBand) {
      particle.vx += (_edgeBand - particle.x) * push;
    } else if (particle.x > 1 - _edgeBand) {
      particle.vx -= (particle.x - (1 - _edgeBand)) * push;
    }

    // The band is a share of each axis, so on the long axis it is the same
    // fraction of the screen but a longer distance — hence the aspect term,
    // which puts the restoring force in the same isotropic units as the
    // velocity it is added to.
    if (particle.y < _edgeBand) {
      particle.vy += (_edgeBand - particle.y) * push * invAspect;
    } else if (particle.y > 1 - _edgeBand) {
      particle.vy -= (particle.y - (1 - _edgeBand)) * push * invAspect;
    }
  }

  /// Advances one particle's answer to the beat: the surge that carries it, the
  /// turn that re-aims it, the radial breath a spring takes back, and the flare
  /// that fades.
  void _stepBeatResponse(
    Particle particle,
    MotionIntensitySpec spec,
    double dt,
    double surgeDecay,
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
      // `dt * _frontGain` normalises the accumulation, so the total a mote picks
      // up crossing the front depends on neither the frame rate nor the front's
      // own geometry.
      final impulse = wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          particle.response *
          (0.35 + 0.65 * particle.depth) *
          dt *
          _frontGain;

      particle.pushVelocity += impulse * _pushGain;
      particle.excitation =
          math.min(1.0, particle.excitation + impulse * _flareGain);

      // The travel. Thrown along the direction the mote was *already* going,
      // turned by its own swerve angle — not outward from the centre.
      //
      // That distinction is the whole design. An outward impulse is never given
      // back, so every beat biases the field away from the middle and the screen
      // slowly empties; that bug is what the returning spring above was
      // introduced to work around, at the cost of the beat producing no travel
      // at all. A kick along the heading is ergodic with respect to the flow —
      // the ensemble has no preferred radial direction — so it can be large
      // enough to see and still leave the field where it found it.
      final heading = math.sqrt(
        particle.vx * particle.vx + particle.vy * particle.vy,
      );
      double dirX, dirY;
      if (heading > 1e-6) {
        dirX = particle.vx / heading;
        dirY = particle.vy / heading;
      } else {
        // Nothing to follow yet — fall back to the wavefront's own direction.
        dirX = wave.swirl;
        dirY = 0;
      }
      final swerve = particle.swerveAngle * wave.swirl;
      final cosS = math.cos(swerve);
      final sinS = math.sin(swerve);

      // Neither the surge nor the turn carries `response`. Stacking every spread
      // that already shapes the push — response, depth and bias together — puts
      // a 25x range on them, so the liveliest motes saturate the cap while
      // typical ones move by a fraction of what they should. Depth alone leaves
      // enough variety without either extreme.
      final carry = wave.strength *
          falloff *
          falloff *
          spec.particleImpulse *
          (0.5 + 0.5 * particle.depth) *
          dt *
          _frontGain;

      particle.surgeX += (dirX * cosS - dirY * sinS) * carry * _surgeGain;
      particle.surgeY += (dirX * sinS + dirY * cosS) * carry * _surgeGain;

      // And the beat re-aims where the mote drifts next, so its path kinks on
      // the music rather than tracing a streamline the music never touched.
      final turn = carry * _swerveGain * particle.swirlBias * wave.swirl;
      final cosT = math.cos(turn);
      final sinT = math.sin(turn);
      final hx = particle.headingX;
      final hy = particle.headingY;
      particle.headingX = hx * cosT - hy * sinT;
      particle.headingY = hx * sinT + hy * cosT;
    }

    // Semi-implicit Euler: velocity first, then position, which is what keeps a
    // spring this stiff from winding itself up.
    particle.pushVelocity -= (_pushOmega * _pushOmega * particle.push +
            2 * _pushDamping * _pushOmega * particle.pushVelocity) *
        dt;
    particle.push =
        (particle.push + particle.pushVelocity * dt).clamp(-_maxPush, _maxPush);

    particle.excitation *= math.exp(-dt / particle.excitationTau);

    particle.surgeX =
        (particle.surgeX * surgeDecay).clamp(-_maxSurge, _maxSurge);
    particle.surgeY =
        (particle.surgeY * surgeDecay).clamp(-_maxSurge, _maxSurge);
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

  /// Distance from the field centre in screen heights, so a wavefront expands as
  /// a circle on screen rather than as an ellipse stretched down the long axis.
  double _distanceFromCentre(Particle particle) {
    final dx = (particle.x - _centreX) * _aspect;
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
  ///
  /// The band starts [_edgeFadeInset] *inside* the border and runs to
  /// [_wrapMargin] outside it. Measuring from the border alone put the entire
  /// fade off screen, where its only effect was that motes held full brightness
  /// right up to the edge and then disappeared.
  double edgeFadeOf(Particle particle) {
    const span = _edgeFadeInset + _wrapMargin;
    final outX = math.max(
        _edgeFadeInset - particle.x, particle.x - (1 - _edgeFadeInset));
    final outY = math.max(
        _edgeFadeInset - particle.y, particle.y - (1 - _edgeFadeInset));
    final out = math.max(outX, outY);
    if (out <= 0) return 1;
    return (1 - out / span).clamp(0.0, 1.0);
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
      aspect: size.width / size.height,
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

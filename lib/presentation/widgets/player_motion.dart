import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/models/beat_map.dart';
import '../../models/song.dart';

/// One frame of beat-derived motion, recomputed each display refresh.
///
/// Everything here is in 0..1 (except [anticipation], which is negative) so
/// consumers can scale it however they like without knowing about tempo, bands
/// or the beat grid.
class BeatFrame {
  /// Beat punch envelope: snaps up on the beat, decays away.
  final double pulse;

  /// A small negative dip just *before* the next beat — the breath a person
  /// takes before a downbeat. Only possible because the grid is known ahead of
  /// time, and it is most of what makes the motion read as human rather than
  /// mechanical.
  final double anticipation;

  /// The settle *after* the punch: a shallow negative overshoot that peaks
  /// around 200ms in and eases back to rest. Something struck does not glide
  /// back to where it started — it passes rest and returns.
  final double rebound;

  /// Signed lateral lean, alternating direction beat to beat and varying in
  /// depth. A person nodding along never repeats the same gesture twice, and a
  /// pulse that does is exactly what reads as a metronome.
  final double sway;

  final double bass;
  final double mid;
  final double air;

  /// Slow in-tempo swell, used for continuous motion between beats.
  final double breath;

  /// Index into the beat map, or -1 before the first beat.
  final int beatIndex;
  final bool isDownbeat;

  /// How hard the current beat lands, 0..1, normalised against the track's own
  /// loudest beats and already carrying the bar accent.
  ///
  /// Distinct from [pulse], which is this strength shaped by the attack/decay
  /// envelope and is therefore near zero at the instant a beat arrives — the
  /// moment consumers that spawn something per beat actually need it.
  final double strength;

  /// Whether this frame is driven by a real beat grid. False means the track is
  /// still being analysed, or has no detectable pulse (ambient, spoken word) —
  /// consumers fall back to [breath] alone.
  final bool hasBeat;

  const BeatFrame({
    this.pulse = 0,
    this.anticipation = 0,
    this.rebound = 0,
    this.sway = 0,
    this.bass = 0,
    this.mid = 0,
    this.air = 0,
    this.breath = 0,
    this.beatIndex = -1,
    this.isDownbeat = false,
    this.strength = 0,
    this.hasBeat = false,
  });

  static const idle = BeatFrame();

  /// The whole beat gesture as one signed number: dip in, punch, overshoot,
  /// settle. Most callers want this rather than the individual terms.
  double get displacement => pulse + anticipation + rebound;

  /// Scales every beat-driven term while leaving the free-running [breath] and
  /// the band energies alone, so a track easing into its grid does not also
  /// stop breathing.
  BeatFrame scaleBeat(double factor) {
    if (factor >= 1) return this;
    return BeatFrame(
      pulse: pulse * factor,
      anticipation: anticipation * factor,
      rebound: rebound * factor,
      sway: sway * factor,
      bass: bass,
      mid: mid,
      air: air,
      breath: breath,
      beatIndex: beatIndex,
      isDownbeat: isDownbeat,
      strength: strength * factor,
      hasBeat: hasBeat,
    );
  }
}

/// Per-intensity scaling. The three settings differ only by these numbers, so
/// there is exactly one place to retune the feel.
class MotionIntensitySpec {
  /// Peak fractional scale added to the cover on a full-strength beat.
  final double coverPunch;

  /// Fractional scale from continuous breathing.
  final double coverBreath;

  /// Peak vertical travel in logical pixels — the cover rides up on the punch
  /// and sinks on the anticipation. Kept tiny: this is a weight shift, not a
  /// bounce.
  final double coverLift;

  /// Peak lean in radians.
  final double coverSway;

  final int particleCount;
  final double particleImpulse;
  final double particleOpacity;

  /// Multiplier on how fast the field travels. Scaled alongside the impulse so
  /// a quieter setting means calmer motion overall, not just smaller beats on
  /// motes that move at the same speed regardless.
  final double particleDrift;

  const MotionIntensitySpec({
    required this.coverPunch,
    required this.coverBreath,
    required this.coverLift,
    required this.coverSway,
    required this.particleCount,
    required this.particleImpulse,
    required this.particleOpacity,
    required this.particleDrift,
  });

  static const _subtle = MotionIntensitySpec(
    coverPunch: 0.035,
    coverBreath: 0.010,
    coverLift: 2.0,
    coverSway: 0.0035,
    particleCount: 28,
    particleImpulse: 0.55,
    particleOpacity: 0.30,
    particleDrift: 0.75,
  );

  static const _balanced = MotionIntensitySpec(
    coverPunch: 0.058,
    coverBreath: 0.014,
    coverLift: 3.2,
    coverSway: 0.0055,
    particleCount: 38,
    particleImpulse: 0.90,
    particleOpacity: 0.39,
    particleDrift: 0.94,
  );

  static const _bold = MotionIntensitySpec(
    coverPunch: 0.092,
    coverBreath: 0.021,
    coverLift: 5.2,
    coverSway: 0.0092,
    particleCount: 52,
    particleImpulse: 1.50,
    particleOpacity: 0.50,
    particleDrift: 1.25,
  );

  /// Floor of the custom slider range — half of [subtle].
  static const _min = MotionIntensitySpec(
    coverPunch: 0.018,
    coverBreath: 0.005,
    coverLift: 1.0,
    coverSway: 0.0018,
    particleCount: 14,
    particleImpulse: 0.28,
    particleOpacity: 0.15,
    particleDrift: 0.38,
  );

  /// Ceiling of the custom slider range — roughly 1.4x [bold].
  static const _max = MotionIntensitySpec(
    coverPunch: 0.13,
    coverBreath: 0.029,
    coverLift: 7.3,
    coverSway: 0.013,
    particleCount: 74,
    particleImpulse: 2.1,
    particleOpacity: 0.70,
    particleDrift: 1.75,
  );

  static MotionIntensitySpec of(PlayerMotionIntensity intensity) {
    return switch (intensity) {
      PlayerMotionIntensity.subtle => _subtle,
      PlayerMotionIntensity.balanced => _balanced,
      PlayerMotionIntensity.bold => _bold,
      PlayerMotionIntensity.custom => _subtle,
    };
  }

  /// Custom intensity from a 0-1 slider where the quartiles correspond to the
  /// three presets (0.25 = subtle, 0.5 = balanced, 0.75 = bold).
  static MotionIntensitySpec custom(double t) {
    t = t.clamp(0.0, 1.0);
    if (t <= 0.25) return _lerpSpec(_min, _subtle, t / 0.25);
    if (t <= 0.5) return _lerpSpec(_subtle, _balanced, (t - 0.25) / 0.25);
    if (t <= 0.75) return _lerpSpec(_balanced, _bold, (t - 0.5) / 0.25);
    return _lerpSpec(_bold, _max, (t - 0.75) / 0.25);
  }

  static MotionIntensitySpec _lerpSpec(
      MotionIntensitySpec a, MotionIntensitySpec b, double t) {
    return MotionIntensitySpec(
      coverPunch: a.coverPunch + (b.coverPunch - a.coverPunch) * t,
      coverBreath: a.coverBreath + (b.coverBreath - a.coverBreath) * t,
      coverLift: a.coverLift + (b.coverLift - a.coverLift) * t,
      coverSway: a.coverSway + (b.coverSway - a.coverSway) * t,
      particleCount:
          (a.particleCount + (b.particleCount - a.particleCount) * t).round(),
      particleImpulse:
          a.particleImpulse + (b.particleImpulse - a.particleImpulse) * t,
      particleOpacity:
          a.particleOpacity + (b.particleOpacity - a.particleOpacity) * t,
      particleDrift: a.particleDrift + (b.particleDrift - a.particleDrift) * t,
    );
  }
}

/// Drives every beat-reactive element on the player screen from a single ticker.
///
/// Both the cover and the particle field listen here, so the per-frame beat math
/// happens once for the whole screen. This follows the same convention as
/// playback state elsewhere in the app: hot-path visual state is published
/// through listenables, not Riverpod, so only the pieces that animate rebuild.
class PlayerMotionController extends ChangeNotifier {
  /// Attack of the beat envelope. Fast up, slow down — the response of something
  /// struck, rather than a symmetric fade that reads as a pulse lamp.
  ///
  /// Attack is absolute: it is the rise time of a physical strike and does not
  /// get shorter because the music is faster. Decay does — see [_decayMsFor].
  static const double _attackMs = 18;

  /// Decay as a fraction of the beat, and the range it is held within.
  ///
  /// A fixed decay is what made fast tracks read as smoothed-out: at 175 BPM a
  /// 190ms tail is still at ~23% of peak when the next beat lands, so successive
  /// punches stacked onto a raised plateau instead of resolving into separate
  /// hits. Tying it to the period keeps the *shape* of the gesture constant
  /// across tempos — the pulse always has the same proportion of the beat to
  /// fall away in. The fraction is set so 500ms (120 BPM) still yields 190ms.
  static const double _decayPeriodFraction = 0.38;
  static const double _minDecayMs = 80;
  static const double _maxDecayMs = 220;

  /// How long before a beat the anticipatory dip starts, capped so it never
  /// eats more than this share of a fast beat.
  static const double _anticipationMs = 60;
  static const double _anticipationPeriodFraction = 0.16;
  static const double _anticipationDepth = 0.22;

  /// Where the overshoot after the punch is deepest, and how deep it goes.
  /// Comfortably inside a beat at any sane tempo, so the settle finishes before
  /// the next punch rather than colliding with it.
  static const double _reboundPeakMs = 210;
  static const double _reboundDepth = 0.16;

  /// Share of the beat the settle is allowed to occupy, and its absolute
  /// ceiling. Ending before the beat does rather than running right up to it is
  /// what keeps the overshoot from bleeding into the next anticipation.
  static const double _reboundWindowFraction = 0.7;
  static const double _maxReboundWindowMs = 600;

  /// How long the motion takes to ease into a freshly arrived beat grid.
  static const double _gridBlendMs = 500;

  /// Downbeats hit full strength and everything else sits below them — that
  /// relative difference is what gives a bar its shape.
  ///
  /// Expressed as a ceiling on offbeats rather than a boost on downbeats
  /// deliberately. Beat strengths are normalised against a track's own loudest
  /// beats, so most sit near 1.0; multiplying downbeats *up* from there just
  /// clamps, and the bar structure disappears on exactly the driving tracks
  /// where it matters most.
  ///
  /// Relaxed as the tempo rises: see [_offbeatLevelFor].
  static const double _offbeatLevelSlow = 0.62;
  static const double _offbeatLevelFast = 0.88;

  /// Beat periods the offbeat ceiling is interpolated between — 120 and 160 BPM.
  static const double _offbeatSlowPeriodMs = 500;
  static const double _offbeatFastPeriodMs = 375;

  /// Beyond this the clock has been seeked or the track changed, so snap
  /// instead of easing.
  static const int _snapThresholdMs = 250;

  /// Fraction of the remaining error corrected per position update. Small
  /// enough that ordinary jitter is invisible, large enough to converge in
  /// well under a second.
  static const double _easeFactor = 0.15;

  Ticker? _ticker;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  BeatMap? _beatMap;
  BeatFrame _frame = BeatFrame.idle;
  PlayerMotionIntensity _intensityEnum = PlayerMotionIntensity.subtle;
  double _customIntensity = 0.5;
  MotionIntensitySpec _spec =
      MotionIntensitySpec.of(PlayerMotionIntensity.subtle);

  bool _enabled = true;
  bool _playing = false;
  bool _appActive = true;
  int _latencyMs = 0;

  /// How much of the beat-driven motion is faded in, 0..1.
  ///
  /// Analysis lands asynchronously, so without this the cover jumps from a free
  /// swell to a locked pulse mid-track. Applied in [_onTick] only — never in
  /// [computeFrame], which stays a pure function of the playhead — and only ever
  /// reset while a real ticker is running, so a detached controller (tests,
  /// anything driving frames by hand) always sees the grid at full strength.
  double _gridBlend = 1;

  /// Anchor for the playhead clock, kept because `player.position` jitters
  /// enough between platform updates to make a beat-locked animation visibly
  /// stutter.
  Duration _anchorPosition = Duration.zero;
  int _anchorWallMs = 0;

  /// Normalisation so a full-strength beat peaks at exactly 1.0.
  ///
  /// Depends on the decay, which now moves with the tempo, so it cannot be a
  /// constant. Memoised on the last decay rather than recomputed per frame: a
  /// track holds one period for minutes at a time, so this is a handful of
  /// transcendentals per tempo change instead of three per frame.
  double _scaleForDecayMs = double.nan;
  double _envelopeScale = 1;

  /// Follows [player]'s clock. The player itself is not retained — only its
  /// streams matter here, and they are cancelled on dispose.
  PlayerMotionController({required AudioPlayer player}) {
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _anchorPosition = player.position;
    _playing = player.playing;

    _positionSub = player.positionStream.listen(_onPosition);
    _stateSub = player.playerStateStream.listen(_onPlayerState);
  }

  /// Detached from any player, for exercising the frame math and the clock
  /// without a platform audio session.
  @visibleForTesting
  PlayerMotionController.forTesting();

  BeatFrame get frame => _frame;
  MotionIntensitySpec get spec => _spec;
  bool get hasBeatMap => _beatMap?.hasBeats ?? false;

  /// Monotonic animation clock. The particle simulation integrates against this,
  /// so it advances by real elapsed seconds rather than assuming a frame rate.
  ///
  /// Deliberately not the raw ticker elapsed: [Ticker.start] restarts from zero,
  /// so every pause/resume would rewind the clock and re-phase every particle at
  /// the same instant. [_elapsedBase] carries the total across stops.
  Duration get elapsed => _elapsed;
  Duration _elapsed = Duration.zero;
  Duration _elapsedBase = Duration.zero;

  /// Must be called once with a vsync provider before the controller animates.
  void attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker(_onTick);
    _syncTicker();
  }

  set beatMap(BeatMap? map) {
    final hadBeats = _beatMap?.hasBeats ?? false;
    _beatMap = map;
    // Only fade in when a grid actually appears mid-playback. Guarding on the
    // ticker keeps hand-driven controllers deterministic.
    if (!hadBeats && (map?.hasBeats ?? false) && (_ticker?.isActive ?? false)) {
      _gridBlend = 0;
    }
  }

  set intensity(PlayerMotionIntensity value) {
    if (_intensityEnum == value) return;
    _intensityEnum = value;
    _applySpec();
  }

  /// Fine-grained intensity for the [custom] setting. Only applied when the
  /// current [intensity] is [PlayerMotionIntensity.custom].
  set customIntensity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_customIntensity == clamped) return;
    _customIntensity = clamped;
    if (_intensityEnum == PlayerMotionIntensity.custom) {
      _applySpec();
    }
  }

  void _applySpec() {
    _spec = _intensityEnum == PlayerMotionIntensity.custom
        ? MotionIntensitySpec.custom(_customIntensity)
        : MotionIntensitySpec.of(_intensityEnum);
    notifyListeners();
  }

  /// Visual offset in milliseconds, compensating audio output latency.
  ///
  /// Wired to a user setting because the correct value is not a property of the
  /// app: wired headphones need ~50 ms while Bluetooth routinely needs 150–250 ms,
  /// and a fixed constant would leave those users with a permanently
  /// out-of-time pulse and no way to fix it.
  set latencyMs(int value) => _latencyMs = value;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _syncTicker();
  }

  /// Tracks app lifecycle, so a backgrounded player is not burning frames.
  set appActive(bool value) {
    if (_appActive == value) return;
    _appActive = value;
    _syncTicker();
  }

  void _onPlayerState(PlayerState state) {
    final playing = state.playing;
    if (_playing != playing) {
      // Re-anchor across the transition so the clock does not jump by however
      // long the player sat paused.
      _anchorPosition = _predictedPosition();
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      _playing = playing;
      _syncTicker();
    }
  }

  void _onPosition(Duration position) {
    final predicted = _predictedPosition();
    final driftMs = position.inMilliseconds - predicted.inMilliseconds;

    if (driftMs.abs() > _snapThresholdMs) {
      // A seek or a track change: snapping is correct, and easing across it
      // would drag the pulse through positions the listener never heard.
      _anchorPosition = position;
    } else {
      _anchorPosition = predicted +
          Duration(
            milliseconds: (driftMs * _easeFactor).round(),
          );
    }
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
  }

  Duration _predictedPosition() {
    if (!_playing) return _anchorPosition;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    return _anchorPosition + Duration(milliseconds: elapsed);
  }

  /// The position the listener is currently *hearing*, which trails the decoder
  /// by the output latency.
  double _visualPositionMs() {
    return _predictedPosition().inMilliseconds.toDouble() - _latencyMs;
  }

  void _syncTicker() {
    final ticker = _ticker;
    if (ticker == null) return;

    final shouldRun = _enabled && _playing && _appActive;
    if (shouldRun && !ticker.isActive) {
      ticker.start();
    } else if (!shouldRun && ticker.isActive) {
      ticker.stop();
      // Bank the clock before it restarts from zero on the next start().
      _elapsedBase = _elapsed;
      // Settle to rest rather than freezing mid-punch.
      _frame = BeatFrame.idle;
      notifyListeners();
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _elapsed;
    _elapsed = _elapsedBase + elapsed;

    if (_gridBlend < 1) {
      final deltaMs = (_elapsed - previous).inMicroseconds / 1000;
      _gridBlend = (_gridBlend + deltaMs / _gridBlendMs).clamp(0.0, 1.0);
    }

    _frame = computeFrame(_visualPositionMs()).scaleBeat(_gridBlend);
    notifyListeners();
  }

  /// Drives one frame by hand, standing in for the ticker so widget tests can
  /// step through beats deterministically.
  @visibleForTesting
  void debugTick(Duration elapsed, double positionMs) {
    _elapsedBase = Duration.zero;
    _elapsed = elapsed;
    _frame = computeFrame(positionMs);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetAnchor(Duration position) {
    _anchorPosition = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _playing = false;
  }

  @visibleForTesting
  void debugOnPosition(Duration position) => _onPosition(position);

  /// Stands in for the player's state stream, so the ticker can be started and
  /// stopped without a platform audio session.
  @visibleForTesting
  void debugSetPlaying(bool playing) =>
      _onPlayerState(PlayerState(playing, ProcessingState.ready));

  @visibleForTesting
  int debugPredictedMs() => _predictedPosition().inMilliseconds;

  @visibleForTesting
  double debugVisualPositionMs() => _visualPositionMs();

  /// Builds the frame for a given playhead position. Separated from the ticker
  /// so it can be driven deterministically in tests.
  @visibleForTesting
  BeatFrame computeFrame(double positionMs) {
    final map = _beatMap;

    final bass = map == null ? 0.0 : map.bandAt(BeatBand.bass, positionMs);
    final mid = map == null ? 0.0 : map.bandAt(BeatBand.mid, positionMs);
    final air = map == null ? 0.0 : map.bandAt(BeatBand.air, positionMs);

    if (map == null || !map.hasBeats) {
      // No grid: a slow free-running swell, lifted by whatever low-end energy
      // the track has. Ambient tracks live here permanently and still move.
      final phase = positionMs / 1000 * 2 * math.pi * 0.16;
      final sine = 0.5 + 0.5 * math.sin(phase);
      return BeatFrame(
        bass: bass,
        mid: mid,
        air: air,
        breath: clamp01(sine * (0.45 + 0.55 * bass)),
        hasBeat: false,
      );
    }

    final index = map.beatIndexAt(positionMs.round());
    final periodMs = map.beatPeriodMsAt(index < 0 ? 0 : index);

    var pulse = 0.0;
    var rebound = 0.0;
    var sway = 0.0;
    var isDownbeat = false;
    var strength = 0.0;
    if (index >= 0) {
      final sinceBeat = positionMs - map.beatsMs[index];
      isDownbeat = map.downbeats[index] == 1;
      strength = clamp01(
        map.beatStrength[index] *
            (isDownbeat ? 1.0 : _offbeatLevelFor(periodMs)),
      );
      pulse = _envelope(sinceBeat, periodMs) * strength;
      rebound = -_reboundBump(sinceBeat, periodMs) * _reboundDepth * strength;
      // Alternating lean, at a depth that varies beat to beat. Both come from
      // the beat index, so the same track leans the same way every play.
      final direction = index.isEven ? 1.0 : -1.0;
      sway = pulse * direction * (0.6 + 0.4 * _beatVariation(index));
    }

    var anticipation = 0.0;
    final nextIndex = index + 1;
    if (nextIndex < map.beatsMs.length) {
      final toNext = map.beatsMs[nextIndex] - positionMs;
      // The dip belongs to the beat it precedes, so it is sized by *that*
      // beat's period rather than the one currently sounding.
      final nextPeriodMs = map.beatPeriodMsAt(nextIndex);
      final window = _anticipationWindowMs(nextPeriodMs);
      if (toNext >= 0 && toNext < window) {
        final nextIsDownbeat = map.downbeats[nextIndex] == 1;
        final strength = map.beatStrength[nextIndex] *
            (nextIsDownbeat ? 1.0 : _offbeatLevelFor(nextPeriodMs));
        // Deepens as the beat approaches, so the cover is at its smallest the
        // instant before it punches. Smoothstepped rather than linear: a linear
        // ramp enters the window at full speed, and that corner is visible.
        final ramp = 1 - toNext / window;
        final eased = ramp * ramp * (3 - 2 * ramp);
        anticipation = -eased * _anticipationDepth * strength;
      }
    }

    // Between beats, breathe on the beat period itself, so even the continuous
    // motion is in time with the music.
    final phaseInBeat = index < 0
        ? 0.0
        : ((positionMs - map.beatsMs[index]) / periodMs).clamp(0.0, 1.0);
    final breath = clamp01(
      (0.5 - 0.5 * math.cos(2 * math.pi * phaseInBeat)) * (0.4 + 0.6 * bass),
    );

    return BeatFrame(
      pulse: clamp01(pulse),
      anticipation: anticipation,
      rebound: rebound,
      sway: sway,
      bass: bass,
      mid: mid,
      air: air,
      breath: breath,
      beatIndex: index,
      isDownbeat: isDownbeat,
      strength: strength,
      hasBeat: true,
    );
  }

  /// `(1 - e^(-t/attack)) * e^(-t/decay)`, normalised to peak at 1, with the
  /// decay scaled to the beat so the punch always has room to resolve before the
  /// next one arrives.
  double _envelope(double sinceBeatMs, double periodMs) {
    if (sinceBeatMs < 0) return 0;
    final decayMs = _decayMsFor(periodMs);
    // Past a few decay constants the contribution is invisible; bail rather
    // than computing two exponentials for nothing.
    if (sinceBeatMs > decayMs * 5) return 0;
    final attack = 1 - math.exp(-sinceBeatMs / _attackMs);
    final decay = math.exp(-sinceBeatMs / decayMs);
    return attack * decay * _scaleFor(decayMs);
  }

  /// Decay constant for a beat of [periodMs]. See [_decayPeriodFraction].
  static double _decayMsFor(double periodMs) =>
      (periodMs * _decayPeriodFraction).clamp(_minDecayMs, _maxDecayMs);

  /// Length of the anticipatory dip before a beat of [periodMs].
  static double _anticipationWindowMs(double periodMs) => math.min(
        _anticipationMs,
        periodMs * _anticipationPeriodFraction,
      );

  /// Offbeat ceiling for a beat of [periodMs].
  ///
  /// At 120 BPM and below, holding offbeats down is what gives a bar its shape.
  /// At 160+ every beat is usually a full kick, and suppressing three in four
  /// there is most of why fast tracks read as one pulse per bar rather than the
  /// rapid train of pulses the music actually has.
  static double _offbeatLevelFor(double periodMs) {
    final t = ((_offbeatSlowPeriodMs - periodMs) /
            (_offbeatSlowPeriodMs - _offbeatFastPeriodMs))
        .clamp(0.0, 1.0);
    return _offbeatLevelSlow + (_offbeatLevelFast - _offbeatLevelSlow) * t;
  }

  /// [_envelopeScale] for [decayMs], recomputing only when the decay moves.
  double _scaleFor(double decayMs) {
    if (decayMs != _scaleForDecayMs) {
      _scaleForDecayMs = decayMs;
      _envelopeScale = _computeEnvelopeScale(decayMs);
    }
    return _envelopeScale;
  }

  /// `(t/τ)²·e^(2(1−t/τ))` — a bump that leaves rest slowly, peaks at exactly 1
  /// when `t == τ`, and falls away. Used negated, so the punch is followed by a
  /// shallow pass below rest instead of a monotonic decay back to it.
  ///
  /// Tapered to zero across the beat, and with the peak pulled in on fast
  /// tempos: an exponential tail alone still has two thirds of its depth left
  /// half a second later, which would leave the cover permanently sitting small
  /// between beats instead of settling.
  double _reboundBump(double sinceBeatMs, double periodMs) {
    if (sinceBeatMs <= 0) return 0;
    // Ends short of the next beat rather than running right up to it, so the
    // settle is finished before the following anticipation opens.
    final window = math.min(
      periodMs * _reboundWindowFraction,
      _maxReboundWindowMs,
    );
    if (sinceBeatMs >= window) return 0;

    final t = sinceBeatMs / math.min(_reboundPeakMs, periodMs * 0.4);
    return t * t * math.exp(2 * (1 - t)) * (1 - sinceBeatMs / window);
  }

  /// A stable 0..1 pseudo-random for a beat index. Cheap integer hash rather
  /// than a Random, so any frame can be recomputed without carrying state.
  static double _beatVariation(int index) {
    var hash = index * 0x27d4eb2d;
    hash ^= hash >> 15;
    hash *= 0x85ebca6b;
    hash ^= hash >> 13;
    return (hash & 0xffff) / 0xffff;
  }

  static double _computeEnvelopeScale(double decayMs) {
    // The peak of the attack/decay product, solved analytically.
    final peakTime = _attackMs * math.log(1 + decayMs / _attackMs);
    final peak =
        (1 - math.exp(-peakTime / _attackMs)) * math.exp(-peakTime / decayMs);
    return peak <= 0 ? 1 : 1 / peak;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    // Ticker.dispose asserts it is not still running, which is exactly the case
    // when the player screen is closed mid-playback.
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

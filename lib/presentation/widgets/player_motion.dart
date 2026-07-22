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

  final double bass;
  final double mid;
  final double air;

  /// Slow in-tempo swell, used for continuous motion between beats.
  final double breath;

  /// Index into the beat map, or -1 before the first beat.
  final int beatIndex;
  final bool isDownbeat;

  /// Whether this frame is driven by a real beat grid. False means the track is
  /// still being analysed, or has no detectable pulse (ambient, spoken word) —
  /// consumers fall back to [breath] alone.
  final bool hasBeat;

  const BeatFrame({
    this.pulse = 0,
    this.anticipation = 0,
    this.bass = 0,
    this.mid = 0,
    this.air = 0,
    this.breath = 0,
    this.beatIndex = -1,
    this.isDownbeat = false,
    this.hasBeat = false,
  });

  static const idle = BeatFrame();

  /// Pulse plus anticipation — the combined signed displacement most callers
  /// actually want.
  double get displacement => pulse + anticipation;
}

/// Per-intensity scaling. The three settings differ only by these numbers, so
/// there is exactly one place to retune the feel.
class MotionIntensitySpec {
  /// Peak fractional scale added to the cover on a full-strength beat.
  final double coverPunch;

  /// Fractional scale from continuous breathing.
  final double coverBreath;

  final int particleCount;
  final double particleImpulse;
  final double particleOpacity;

  const MotionIntensitySpec({
    required this.coverPunch,
    required this.coverBreath,
    required this.particleCount,
    required this.particleImpulse,
    required this.particleOpacity,
  });

  static const _subtle = MotionIntensitySpec(
    coverPunch: 0.035,
    coverBreath: 0.010,
    particleCount: 22,
    particleImpulse: 0.55,
    particleOpacity: 0.30,
  );

  static const _balanced = MotionIntensitySpec(
    coverPunch: 0.065,
    coverBreath: 0.016,
    particleCount: 32,
    particleImpulse: 1.0,
    particleOpacity: 0.42,
  );

  static const _bold = MotionIntensitySpec(
    coverPunch: 0.105,
    coverBreath: 0.024,
    particleCount: 44,
    particleImpulse: 1.7,
    particleOpacity: 0.55,
  );

  static MotionIntensitySpec of(PlayerMotionIntensity intensity) {
    return switch (intensity) {
      PlayerMotionIntensity.subtle => _subtle,
      PlayerMotionIntensity.balanced => _balanced,
      PlayerMotionIntensity.bold => _bold,
    };
  }
}

/// Drives every beat-reactive element on the player screen from a single ticker.
///
/// Both the cover and the particle field listen here, so the per-frame beat math
/// happens once for the whole screen. This follows the same convention as
/// playback state elsewhere in the app: hot-path visual state is published
/// through listenables, not Riverpod, so only the pieces that animate rebuild.
class PlayerMotionController extends ChangeNotifier {
  /// Attack and decay of the beat envelope. Fast up, slow down — the response
  /// of something struck, rather than a symmetric fade that reads as a pulse
  /// lamp.
  static const double _attackMs = 18;
  static const double _decayMs = 190;

  /// How long before a beat the anticipatory dip starts.
  static const double _anticipationMs = 60;
  static const double _anticipationDepth = 0.22;

  /// Downbeats hit full strength and everything else sits below them — that
  /// relative difference is what gives a bar its shape.
  ///
  /// Expressed as a ceiling on offbeats rather than a boost on downbeats
  /// deliberately. Beat strengths are normalised against a track's own loudest
  /// beats, so most sit near 1.0; multiplying downbeats *up* from there just
  /// clamps, and the bar structure disappears on exactly the driving tracks
  /// where it matters most.
  static const double _offbeatLevel = 0.62;

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
  MotionIntensitySpec _spec =
      MotionIntensitySpec.of(PlayerMotionIntensity.subtle);

  bool _enabled = true;
  bool _playing = false;
  bool _appActive = true;
  int _latencyMs = 0;

  /// Anchor for the playhead clock, kept because `player.position` jitters
  /// enough between platform updates to make a beat-locked animation visibly
  /// stutter.
  Duration _anchorPosition = Duration.zero;
  int _anchorWallMs = 0;

  /// Normalisation so a full-strength beat peaks at exactly 1.0.
  late final double _envelopeScale = _computeEnvelopeScale();

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

  /// Ticker elapsed time. The particle simulation integrates against this, so
  /// it advances by real elapsed seconds rather than assuming a frame rate.
  Duration get elapsed => _elapsed;
  Duration _elapsed = Duration.zero;

  /// Must be called once with a vsync provider before the controller animates.
  void attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker(_onTick);
    _syncTicker();
  }

  set beatMap(BeatMap? map) => _beatMap = map;

  set intensity(PlayerMotionIntensity value) {
    final next = MotionIntensitySpec.of(value);
    if (next == _spec) return;
    _spec = next;
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
      // Settle to rest rather than freezing mid-punch.
      _frame = BeatFrame.idle;
      notifyListeners();
    }
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    _frame = computeFrame(_visualPositionMs());
    notifyListeners();
  }

  /// Drives one frame by hand, standing in for the ticker so widget tests can
  /// step through beats deterministically.
  @visibleForTesting
  void debugTick(Duration elapsed, double positionMs) {
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
    var isDownbeat = false;
    if (index >= 0) {
      final sinceBeat = positionMs - map.beatsMs[index];
      isDownbeat = map.downbeats[index] == 1;
      final strength =
          map.beatStrength[index] * (isDownbeat ? 1.0 : _offbeatLevel);
      pulse = _envelope(sinceBeat) * strength;
    }

    var anticipation = 0.0;
    final nextIndex = index + 1;
    if (nextIndex < map.beatsMs.length) {
      final toNext = map.beatsMs[nextIndex] - positionMs;
      if (toNext >= 0 && toNext < _anticipationMs) {
        final nextIsDownbeat = map.downbeats[nextIndex] == 1;
        final strength = map.beatStrength[nextIndex] *
            (nextIsDownbeat ? 1.0 : _offbeatLevel);
        // Deepens as the beat approaches, so the cover is at its smallest the
        // instant before it punches.
        final ramp = 1 - toNext / _anticipationMs;
        anticipation = -ramp * _anticipationDepth * strength;
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
      bass: bass,
      mid: mid,
      air: air,
      breath: breath,
      beatIndex: index,
      isDownbeat: isDownbeat,
      hasBeat: true,
    );
  }

  /// `(1 - e^(-t/attack)) * e^(-t/decay)`, normalised to peak at 1.
  double _envelope(double sinceBeatMs) {
    if (sinceBeatMs < 0) return 0;
    // Past a few decay constants the contribution is invisible; bail rather
    // than computing two exponentials for nothing.
    if (sinceBeatMs > _decayMs * 5) return 0;
    final attack = 1 - math.exp(-sinceBeatMs / _attackMs);
    final decay = math.exp(-sinceBeatMs / _decayMs);
    return attack * decay * _envelopeScale;
  }

  static double _computeEnvelopeScale() {
    // The peak of the attack/decay product, solved analytically.
    final peakTime = _attackMs * math.log(1 + _decayMs / _attackMs);
    final peak =
        (1 - math.exp(-peakTime / _attackMs)) * math.exp(-peakTime / _decayMs);
    return peak <= 0 ? 1 : 1 / peak;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

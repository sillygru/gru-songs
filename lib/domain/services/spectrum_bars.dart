import 'dart:math' as math;

import '../models/beat_map.dart';

/// The frame math behind the four-bar audio visualiser.
///
/// Pure, so the ballistics can be tested directly rather than inferred from a
/// screenshot — the same reason `shuffle_weight_service.dart` is pure.
///
/// One bar per [BeatBand], left to right: bass, low-mid, mid, air. The band
/// envelopes come out of the offline analysis already normalised against each
/// band's own 99th percentile, so no bar sits permanently dark on a track with
/// little top end — what each bar shows is that band relative to how loud that
/// band gets in *this* song.
class SpectrumBars {
  SpectrumBars._();

  /// One bar per band. The two are the same number by construction, not by
  /// coincidence: the visualiser exists to show the bands.
  static const int barCount = 4;

  /// Rise and fall time constants, in seconds.
  ///
  /// Deliberately short. These exist to interpolate between the stored
  /// envelope's 30 frames a second and the display's 60 or 120, and to keep a
  /// single frame of noise from making a bar twitch — not to make the motion
  /// pretty. Anything slower is the bar drawing its own animation instead of
  /// the song's.
  ///
  /// The first version of this used 45/190ms on top of an analyser that was
  /// itself smoothing with a 180ms fall. The two stacked into a ~370ms glide,
  /// which is where "too smoothed out" came from: measured against real audio,
  /// half the kicks in a dense track produced no visible rise at all. The
  /// analyser now stores a peak follower and these do the rest; below ~45ms of
  /// release the returns flatten and the bars start to read as jittery.
  static const double attackTau = 0.010;
  static const double releaseTau = 0.055;

  /// Height a bar never falls below, as a fraction of the full height.
  ///
  /// Zero-height bars in a rest read as a bug — the widget looks broken rather
  /// than quiet. This is also what the bars sit at when nothing is playing.
  /// Low, so that a quiet passage actually looks quiet.
  static const double floor = 0.05;

  /// Expansion applied to raw band energy. Above 1 deepens the dynamics.
  ///
  /// Band energy is stored as a log magnitude normalised against the band's own
  /// 99th percentile, and log magnitudes cluster high — left alone, everything
  /// hovers near the top and the bars all look the same height. A mild
  /// expansion puts the contrast back.
  static const double _gamma = 1.15;

  /// Extra punch mixed into each bar straight from the beat grid, indexed by
  /// band.
  ///
  /// Band frames are 33 ms apart, which is enough to smear a kick's attack past
  /// the point where it still reads as on the beat. The grid knows the exact
  /// millisecond, so the low bars borrow from it. Nothing is added to mid and
  /// air: a beat is a thing you feel in the low end, and punching the treble
  /// bars on it is what makes cheap visualisers look like four copies of one
  /// bar.
  ///
  /// Small, and smaller than it was: now that the stored envelope keeps its
  /// transients, the bands carry the kick themselves and this is only closing
  /// the gap left by their 33ms frame spacing. Any more and the bars would be
  /// reporting the grid rather than the audio.
  static const List<double> beatWeights = [0.18, 0.09, 0.0, 0.0];

  /// Attack of the beat punch, in milliseconds — the rise time of a struck
  /// thing. Matches `PlayerMotionController`, so the bars and the cover punch
  /// on the same edge.
  static const double _punchAttackMs = 18;

  /// Punch decay as a share of the beat period, and the range it is held in, so
  /// the shape of the gesture stays constant from 70 to 180 BPM.
  static const double _punchDecayFraction = 0.30;
  static const double _punchMinDecayMs = 70;
  static const double _punchMaxDecayMs = 180;

  /// Depth and rate of the per-bar idle breath. Kept small — this exists so
  /// four bands moving together do not render as four identical rectangles, not
  /// as motion in its own right.
  static const double _breathDepth = 0.03;
  static const double _breathHz = 0.21;

  /// Moves [level] toward [target] over [dtSeconds], rising fast and falling
  /// slowly.
  ///
  /// Frame-rate independent: `1 - e^(-dt/tau)` means two 8 ms steps land in the
  /// same place as one 16 ms step, so the bars behave identically at 60 Hz,
  /// 120 Hz and under the power-save frame cap. A plain `level += (target -
  /// level) * k` — what the old visualiser used — is a different animation on
  /// every device.
  static double advance(double level, double target, double dtSeconds) =>
      advanceWithTau(level, target, dtSeconds, tauFor(level, target));

  /// Rise or fall constant for a bar moving from [level] to [target].
  static double tauFor(double level, double target) =>
      target > level ? attackTau : releaseTau;

  /// [advance] with the time constant supplied, for callers cross-fading
  /// between two responses.
  static double advanceWithTau(
    double level,
    double target,
    double dtSeconds,
    double tau,
  ) {
    if (dtSeconds <= 0) return level;
    final k = 1 - math.exp(-dtSeconds / tau);
    return level + (target - level) * k;
  }

  /// Maps raw band energy in 0..1 to a bar height in [floor]..1.
  static double shape(double raw) {
    final clamped = clamp01(raw);
    return floor + (1 - floor) * math.pow(clamped, _gamma).toDouble();
  }

  /// Beat punch [sinceBeatMs] after a beat of [periodMs], peaking at 1.
  ///
  /// `(1 - e^(-t/attack)) * e^(-t/decay)`, normalised — the same envelope the
  /// cover pulses on.
  static double punch(double sinceBeatMs, double periodMs) {
    if (sinceBeatMs < 0) return 0;
    final decayMs = (periodMs * _punchDecayFraction)
        .clamp(_punchMinDecayMs, _punchMaxDecayMs);
    // Past a few decay constants this is invisible; bail rather than paying for
    // two exponentials to add nothing.
    if (sinceBeatMs > decayMs * 5) return 0;

    final attack = 1 - math.exp(-sinceBeatMs / _punchAttackMs);
    final decay = math.exp(-sinceBeatMs / decayMs);
    return attack * decay * _peakScale(decayMs);
  }

  /// A small per-bar swell, so a passage where every band moves together still
  /// has four distinguishable bars. Phase is derived from the bar index, so a
  /// given bar always breathes the same way.
  static double breath(int bar, double elapsedSeconds) {
    final phase = 2 * math.pi * (_breathHz * elapsedSeconds + bar * 0.37);
    return 1 + _breathDepth * math.sin(phase);
  }

  /// Bar targets for [positionMs] of [map], written into [out].
  ///
  /// Targets, not levels: the caller runs them through [advance] so the bars
  /// keep their ballistics. Returns false when the map has no usable band data,
  /// which is the caller's cue to stay on the idle animation.
  static bool targetsAt(BeatMap map, double positionMs, List<double> out) {
    if (map.bandFrameCount == 0) return false;

    for (var i = 0; i < barCount; i++) {
      out[i] = shape(map.bandAt(BeatBand.values[i], positionMs));
    }

    if (!map.hasBeats) return true;

    final index = map.beatIndexAt(positionMs.round());
    if (index < 0) return true;

    final periodMs = map.beatPeriodMsAt(index);
    final hit = punch(positionMs - map.beatsMs[index], periodMs) *
        map.beatStrength[index];
    if (hit <= 0) return true;

    for (var i = 0; i < barCount; i++) {
      final weight = beatWeights[i];
      if (weight == 0) continue;
      // Added into the headroom above the current target rather than onto it,
      // so a bar already at full does not clip and lose the beat entirely.
      out[i] = out[i] + (1 - out[i]) * hit * weight;
    }
    return true;
  }

  /// Peak of the attack/decay product, solved analytically and memoised: a
  /// track holds one tempo for minutes, so this is a few transcendentals per
  /// tempo change rather than per frame.
  static double _peakScaleForDecayMs = double.nan;
  static double _peakScaleValue = 1;

  static double _peakScale(double decayMs) {
    if (decayMs != _peakScaleForDecayMs) {
      _peakScaleForDecayMs = decayMs;
      final peakTime = _punchAttackMs * math.log(1 + decayMs / _punchAttackMs);
      final peak = (1 - math.exp(-peakTime / _punchAttackMs)) *
          math.exp(-peakTime / decayMs);
      _peakScaleValue = peak <= 0 ? 1 : 1 / peak;
    }
    return _peakScaleValue;
  }
}

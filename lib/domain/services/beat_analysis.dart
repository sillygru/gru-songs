/// Offline rhythmic analysis: mono PCM in, a `BeatMap` out.
///
/// The shape of this pipeline is deliberate, and it is *not* "detect loud
/// moments". A person listening to music does not react to each transient —
/// they hear onsets, infer a steady tempo, and tap a regular pulse, continuing
/// to tap through a quiet bar. Reproducing that is what makes the resulting
/// motion feel human rather than twitchy:
///
///   1. STFT → per-band log magnitude
///   2. half-wave-rectified spectral flux → onset strength envelope
///   3. harmonic-summed autocorrelation under a perceptual tempo prior, then a
///      low-band check for a beat between the beats → beat period
///   4. dynamic programming → the beat sequence that best balances landing on
///      onsets against staying metrically regular (Ellis 2007)
///
/// Step 4 is the one that matters. Thresholding step 2 directly — which is what
/// this file replaces — can only ever chase transients.
///
/// The harmonic summation in step 3 is not decoration either: without it the
/// autocorrelation of ordinary dance music peaks at *twice* the beat, and fast
/// tracks get tracked at half speed.
///
/// Everything here is pure and synchronous so it can run in an isolate and be
/// tested directly against synthetic audio.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../models/beat_map.dart';

/// Sample rate the analyser expects. Callers must resample to this.
///
/// These three constants are librosa's defaults, which is the configuration the
/// reference beat-tracking implementations are tuned against. Changing them
/// means retuning the tempo prior and DP tightness, so don't, casually.
const int analysisSampleRate = 22050;
const int analysisFftSize = 2048;
const int analysisHopSize = 512;

/// Frames per second of the onset envelope: 22050 / 512 ≈ 43.07.
const double analysisFps = analysisSampleRate / analysisHopSize;

/// Number of log-spaced bands the onset envelope is computed over.
///
/// Four bands would be too coarse: a melody moving within one wide band barely
/// registers as flux even though a listener plainly hears the note change.
/// Forty perceptually spaced bands catch that while staying cheap.
const int _onsetBandCount = 40;
const double _onsetBandLowHz = 40;
const double _onsetBandHighHz = 11025;

/// Edges of the four bands exposed for visuals, in Hz.
const List<double> _visualBandEdgesHz = [20, 150, 800, 4000, 11025];

/// Tempo search range, 40–240 BPM.
const double _minBpm = 40;
const double _maxBpm = 240;

/// Centre of the tempo prior. 120 BPM is where human tempo perception clusters.
///
/// The prior alone is *not* enough to stop the autocorrelation locking onto
/// half-time — see [_estimateBeatPeriod]. Sigma is librosa's `std_bpm` default,
/// deliberately wide so a genuine 170–180 BPM track is not penalised into its
/// own half.
const double _tempoPriorCentreSec = 0.5;
const double _tempoPriorOctaveSigma = 1.0;

/// Weights on the 2nd and 3rd harmonics when scoring a candidate beat period.
/// See [_estimateBeatPeriod] for why summing harmonics is what picks the
/// fundamental out of its multiples.
const double _harmonic2Weight = 0.5;
const double _harmonic3Weight = 0.25;

/// Bounds on the half-time rescue in [_correctHalfTime].
///
/// Deliberately narrow. It only ever fires on estimates slow enough to be
/// suspicious, and only when doubling lands somewhere a person would still call
/// a tempo — so it cannot turn a genuine 110 BPM track into 220.
const double _halfTimeSuspectBpm = 100;
const double _halfTimeMaxBpm = 190;

/// How strong the kicks *between* the detected beats must be, relative to the
/// kicks on them, before the tempo is judged to be double what was estimated.
const double _halfTimeMidRatio = 0.7;

/// Upper edge of the low band used by [_correctHalfTime], in Hz. Kick territory:
/// the whole point is to ask a question hi-hats cannot answer.
const double _bassOnsetMaxHz = 160;

/// How strongly the DP penalises deviation from the estimated beat period.
/// Higher is more metronomic, lower follows onsets more loosely.
const double _dpTightness = 100;

/// Minimum 95th-percentile raw onset flux for a track to be considered
/// percussive enough to carry a beat grid.
///
/// The envelope is standard-deviation normalised before tracking, which means
/// *any* input — a held organ chord, tape hiss — can be amplified until it looks
/// like a rhythm. This gate is applied to the raw envelope beforehand.
/// Measured separation is wide: percussive material sits at 3–40 even when
/// mastered 34 dB down, while sustained tones and beatless pads sit at 0.007–0.14.
/// A beatless track is not a failure — it keeps its band envelopes and drives
/// idle breathing instead, which is the honest response to ambient music.
const double _minPercussiveFlux = 0.5;

/// Compression applied to magnitudes before differencing.
///
/// `log1p` rather than dB: it tends to zero as the signal does, so silence
/// produces no flux. A dB floor would turn dither noise into huge spurious
/// onsets during quiet passages.
const double _logGamma = 1000;

/// Analyses [samples] (mono, [sampleRate] Hz, nominally -1..1).
///
/// Returns [BeatMap.empty] for input too short to hold a tempo, or for audio
/// with no detectable rhythmic content.
BeatMap analyzeBeats(Float32List samples,
    {int sampleRate = analysisSampleRate}) {
  final durationMs = (samples.length / sampleRate * 1000).round();

  // Frames are *centred*: frame f covers samples [f*hop - fftSize/2,
  // f*hop + fftSize/2), so frame f is exactly f*hop/sr seconds in. Uncentred
  // framing biases every detected onset early by a fraction of the window,
  // which shows up as visuals that consistently fire ahead of the sound.
  final frameCount = 1 + samples.length ~/ analysisHopSize;
  // Below ~2s there is not enough evidence for a tempo, and the autocorrelation
  // would be dominated by edge effects.
  if (frameCount < analysisFps * 2) {
    return BeatMap.empty(durationMs: durationMs);
  }

  final spectra = _computeEnvelopes(samples, frameCount);
  final onset = spectra.onset;
  final bands = _packBands(spectra.bands, frameCount, sampleRate);

  /// A track with usable band envelopes but no beat grid. Ambient and spoken
  /// word land here and still get to breathe.
  BeatMap beatless() => BeatMap(
        version: BeatMap.currentVersion,
        durationMs: durationMs,
        bpm: 0,
        beatsMs: Int32List(0),
        beatStrength: Float32List(0),
        downbeats: Uint8List(0),
        bands: bands,
      );

  if (!_isPercussive(onset)) return beatless();

  final normalized = _normalizeOnset(onset);
  if (normalized == null) return beatless();

  final estimated = _estimateBeatPeriod(normalized);
  if (estimated == null) return beatless();
  final periodFrames = _correctHalfTime(spectra.bassOnset, estimated);

  final localScore = _smoothForDp(normalized, periodFrames);
  final beatFrames = _trackBeats(localScore, periodFrames);
  if (beatFrames.isEmpty) return beatless();

  final beatsMs = Int32List(beatFrames.length);
  for (var i = 0; i < beatFrames.length; i++) {
    // Parabolic interpolation recovers sub-frame position: a frame is 23ms, and
    // quantising every beat to that grid is audible-adjacent as visual slop.
    final refined = _refinePeak(localScore, beatFrames[i]);
    beatsMs[i] = (refined * analysisHopSize / sampleRate * 1000).round();
  }

  final strength = _beatStrengths(normalized, beatFrames);
  final downbeats = _findDownbeats(strength);
  final bpm = _bpmFromBeats(beatsMs, periodFrames, sampleRate);

  return BeatMap(
    version: BeatMap.currentVersion,
    durationMs: durationMs,
    bpm: bpm,
    beatsMs: beatsMs,
    beatStrength: strength,
    downbeats: downbeats,
    bands: bands,
  );
}

/// Whether [onset] carries enough genuine transient content to be worth
/// tracking. See [_minPercussiveFlux].
bool _isPercussive(Float32List onset) {
  if (onset.isEmpty) return false;
  final sorted = onset.toList()..sort();
  final p95 =
      sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
  return p95 >= _minPercussiveFlux;
}

/// Diagnostic hook: the half-time rescue, which is a safety net under
/// [_estimateBeatPeriod] and so is not reached by any input the estimator
/// already gets right. Exposed so its fire and no-fire behaviour can be pinned
/// directly rather than left to whichever synthetic happens to defeat the
/// harmonic scoring.
double debugCorrectHalfTime(Float32List bassOnset, double period) =>
    _correctHalfTime(bassOnset, period);

/// Diagnostic hook: percentiles of the raw (pre-normalisation) onset envelope.
/// Used to calibrate [_minPercussiveFlux] against real and synthetic material.
List<double> debugOnsetPercentiles(Float32List samples) {
  final frameCount = 1 + samples.length ~/ analysisHopSize;
  if (frameCount < analysisFps * 2) return const [0, 0, 0];
  final onset = _computeEnvelopes(samples, frameCount).onset;
  final sorted = onset.toList()..sort();
  double at(double q) =>
      sorted[math.min(sorted.length - 1, (sorted.length * q).floor())];
  return [at(0.5), at(0.95), at(0.99)];
}

class _Envelopes {
  final Float32List onset;

  /// The same flux restricted to the low bands — kicks only. Used by
  /// [_correctHalfTime], which needs to distinguish a kick from a hi-hat.
  final Float32List bassOnset;

  final List<Float32List> bands;

  _Envelopes(this.onset, this.bassOnset, this.bands);
}

/// One STFT pass producing both the onset envelope and the four visual band
/// envelopes. They share the magnitude spectrum, so computing them together
/// halves the FFT work.
_Envelopes _computeEnvelopes(Float32List samples, int frameCount) {
  final fft = _Fft(analysisFftSize);
  final window = _hannWindow(analysisFftSize);
  final re = Float64List(analysisFftSize);
  final im = Float64List(analysisFftSize);
  final binCount = analysisFftSize ~/ 2 + 1;
  final magnitude = Float64List(binCount);

  final onsetEdges = _logBandEdges(
    _onsetBandCount,
    _onsetBandLowHz,
    _onsetBandHighHz,
    binCount,
  );
  final visualEdges = _fixedBandEdges(_visualBandEdgesHz, binCount);

  // How many of the log-spaced onset bands sit entirely below _bassOnsetMaxHz.
  // Derived from the edges rather than hardcoded, so retuning the band layout
  // cannot silently move the low-band cutoff somewhere else.
  final binWidth = analysisSampleRate / analysisFftSize;
  var bassBandCount = 0;
  while (bassBandCount < _onsetBandCount &&
      onsetEdges[bassBandCount + 1] * binWidth <= _bassOnsetMaxHz) {
    bassBandCount++;
  }

  final onset = Float32List(frameCount);
  final bassOnset = Float32List(frameCount);
  final bands = List.generate(
    BeatBand.values.length,
    (_) => Float32List(frameCount),
    growable: false,
  );

  var prevLog = Float64List(_onsetBandCount);
  var curLog = Float64List(_onsetBandCount);
  // Normalises magnitudes to roughly 0..1 regardless of FFT size, so _logGamma
  // means the same thing at any window length.
  final magScale = 2.0 / analysisFftSize;

  final half = analysisFftSize ~/ 2;

  for (var frame = 0; frame < frameCount; frame++) {
    final start = frame * analysisHopSize - half;
    for (var i = 0; i < analysisFftSize; i++) {
      final index = start + i;
      re[i] = (index < 0 || index >= samples.length)
          ? 0
          : samples[index] * window[i];
      im[i] = 0;
    }
    fft.transform(re, im);

    for (var bin = 0; bin < binCount; bin++) {
      magnitude[bin] =
          math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]) * magScale;
    }

    for (var b = 0; b < _onsetBandCount; b++) {
      curLog[b] = math.log(
        1 + _logGamma * _meanBins(magnitude, onsetEdges[b], onsetEdges[b + 1]),
      );
    }

    if (frame > 0) {
      var flux = 0.0;
      var bassFlux = 0.0;
      for (var b = 0; b < _onsetBandCount; b++) {
        final delta = curLog[b] - prevLog[b];
        // Half-wave rectified: only energy *appearing* is an onset. Energy
        // dying away is a note ending, which nobody taps to.
        if (delta > 0) {
          flux += delta;
          if (b < bassBandCount) bassFlux += delta;
        }
      }
      onset[frame] = flux;
      bassOnset[frame] = bassFlux;
    }

    for (var b = 0; b < BeatBand.values.length; b++) {
      bands[b][frame] = math.log(
        1 +
            _logGamma *
                _meanBins(magnitude, visualEdges[b], visualEdges[b + 1]),
      );
    }

    final swap = prevLog;
    prevLog = curLog;
    curLog = swap;
  }

  return _Envelopes(onset, bassOnset, bands);
}

double _meanBins(Float64List magnitude, int start, int end) {
  if (end <= start) return 0;
  var sum = 0.0;
  for (var i = start; i < end; i++) {
    sum += magnitude[i];
  }
  return sum / (end - start);
}

/// Removes slow loudness drift and puts the envelope on a scale-free footing.
///
/// Subtracting a local mean is what lets a quiet verse and a loud chorus get the
/// same sensitivity; dividing by the standard deviation is what lets one set of
/// DP constants work across every track.
Float32List? _normalizeOnset(Float32List onset) {
  final windowFrames = math.max(3, (analysisFps * 0.4).round());
  final detrended = Float32List(onset.length);
  final running = _RunningMean(windowFrames);

  for (var i = 0; i < onset.length; i++) {
    final mean = running.add(onset[i]);
    final value = onset[i] - mean;
    detrended[i] = value > 0 ? value : 0;
  }

  var sum = 0.0;
  for (final v in detrended) {
    sum += v;
  }
  final mean = sum / detrended.length;
  var variance = 0.0;
  for (final v in detrended) {
    final d = v - mean;
    variance += d * d;
  }
  final std = math.sqrt(variance / detrended.length);
  // Effectively silent, or a pure tone with no onsets at all.
  if (std < 1e-9) return null;

  for (var i = 0; i < detrended.length; i++) {
    detrended[i] = detrended[i] / std;
  }
  return detrended;
}

/// Centred moving mean over a fixed window.
class _RunningMean {
  final int size;
  final Float64List _buffer;
  int _count = 0;
  int _index = 0;
  double _sum = 0;

  _RunningMean(this.size) : _buffer = Float64List(size);

  double add(double value) {
    if (_count < size) {
      _count++;
    } else {
      _sum -= _buffer[_index];
    }
    _buffer[_index] = value;
    _sum += value;
    _index = (_index + 1) % size;
    return _sum / _count;
  }
}

/// Autocorrelates the onset envelope under a log-Gaussian tempo prior and
/// returns the best beat period, in frames.
///
/// A candidate is scored on its own correlation *plus* a weighted share of its
/// 2nd and 3rd harmonics, which is what picks the beat out of its own multiples.
/// The raw autocorrelation of real dance music is routinely *strongest* at twice
/// the beat — kick-clap-kick-clap repeats on a two-beat period, and the bar on
/// four — so plain argmax under a 120 BPM prior collapses a 175 BPM track to 87.
/// Summing harmonics inverts that: if `L` is the true period then `acf(2L)` and
/// `acf(3L)` are strong too and all of it accrues to `L`, while the half-time
/// candidate `2L` can only collect `acf(2L)` and `acf(4L)`. It does not
/// over-correct downward either — with no eighth-note content `acf(L/2)` sits in
/// the anti-correlation trough, so `L/2` never wins on the strength of `acf(L)`
/// alone.
double? _estimateBeatPeriod(Float32List onset) {
  final minLag = math.max(2, (analysisFps * 60 / _maxBpm).floor());
  final maxLag = math.min(
    onset.length ~/ 2,
    (analysisFps * 60 / _minBpm).ceil(),
  );
  if (maxLag <= minLag) return null;

  // Harmonics reach past the tempo search range, so the correlation is computed
  // out to 3x before any candidate is scored.
  final acfMaxLag = math.min(onset.length - 1, maxLag * 3);
  final acf = Float64List(acfMaxLag + 1);
  for (var lag = minLag; lag <= acfMaxLag; lag++) {
    var correlation = 0.0;
    for (var i = lag; i < onset.length; i++) {
      correlation += onset[i] * onset[i - lag];
    }
    acf[lag] = correlation / (onset.length - lag);
  }

  final centreLag = _tempoPriorCentreSec * analysisFps;
  final invLn2 = 1 / math.ln2;

  var bestLag = -1;
  var bestScore = double.negativeInfinity;

  for (var lag = minLag; lag <= maxLag; lag++) {
    var correlation = acf[lag];
    final lag2 = lag * 2;
    if (lag2 <= acfMaxLag) correlation += _harmonic2Weight * acf[lag2];
    final lag3 = lag * 3;
    if (lag3 <= acfMaxLag) correlation += _harmonic3Weight * acf[lag3];

    final octaves = math.log(lag / centreLag) * invLn2;
    final prior = math.exp(
      -0.5 * math.pow(octaves / _tempoPriorOctaveSigma, 2),
    );
    final score = correlation * prior;

    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }

  if (bestLag < 0 || bestScore <= 0) return null;
  return bestLag.toDouble();
}

/// Halves [period] when the low end says there is a kick *between* every pair of
/// detected beats.
///
/// A safety net under [_estimateBeatPeriod], not a replacement for it: harmonic
/// summation is a strong bias toward the fundamental, not a guarantee, and a
/// track that lands at half-time anyway pulses once every 0.6–0.8s instead of
/// two or three times a second.
///
/// The test keys on low-band flux specifically. Asked of the full onset envelope
/// it would be answered "yes" by any track with eighth-note hi-hats, and a
/// leisurely 80 BPM song would be doubled into a twitchy 160. Asked of the kick
/// band, the question is whether the listener is *feeling* a beat in between,
/// which hats and vocal syllables cannot fake.
double _correctHalfTime(Float32List bassOnset, double period) {
  final bpm = 60 * analysisFps / period;
  // Only ever fires where the reported failure lives: an implausibly slow
  // estimate that would double into a real tempo.
  if (bpm >= _halfTimeSuspectBpm) return period;
  if (bpm * 2 > _halfTimeMaxBpm) return period;

  final half = period / 2;
  final step = period.round();
  if (step < 2 || bassOnset.length < step * 4) return period;

  // Phase of the strongest kick comb at the estimated period.
  var bestPhase = 0;
  var bestTotal = -1.0;
  for (var phase = 0; phase < step; phase++) {
    var total = 0.0;
    for (var t = phase.toDouble(); t < bassOnset.length; t += period) {
      total += bassOnset[t.round()];
    }
    if (total > bestTotal) {
      bestTotal = total;
      bestPhase = phase;
    }
  }
  if (bestTotal <= 0) return period;

  var onSum = 0.0;
  var onCount = 0;
  var midSum = 0.0;
  var midCount = 0;
  for (var t = bestPhase.toDouble(); t < bassOnset.length; t += period) {
    onSum += bassOnset[t.round()];
    onCount++;
    final mid = t + half;
    if (mid < bassOnset.length) {
      midSum += bassOnset[mid.round()];
      midCount++;
    }
  }
  if (onCount == 0 || midCount == 0) return period;

  final onEnergy = onSum / onCount;
  final midEnergy = midSum / midCount;
  if (onEnergy <= 0) return period;

  return midEnergy >= _halfTimeMidRatio * onEnergy ? half : period;
}

/// Gaussian smoothing with a width tied to the beat period, so the DP scores a
/// slightly blurred onset envelope and is not derailed by one-frame jitter.
Float32List _smoothForDp(Float32List onset, double period) {
  final std = period / 32;
  final radius = math.max(1, (period).round());
  final window = Float64List(radius * 2 + 1);
  for (var i = -radius; i <= radius; i++) {
    window[i + radius] = math.exp(-0.5 * math.pow(i / std, 2));
  }

  final out = Float32List(onset.length);
  for (var i = 0; i < onset.length; i++) {
    var sum = 0.0;
    final from = math.max(0, i - radius);
    final to = math.min(onset.length - 1, i + radius);
    for (var j = from; j <= to; j++) {
      sum += onset[j] * window[j - i + radius];
    }
    out[i] = sum;
  }
  return out;
}

/// Ellis's dynamic-programming beat tracker.
///
/// Maximises `sum(onset strength at beats) + tightness * regularity`, so the
/// chosen sequence lands on real onsets *and* keeps a steady period. This is
/// what carries the pulse through a bar of silence: skipping beats costs more
/// than tapping through an empty stretch.
List<int> _trackBeats(Float32List localScore, double period) {
  final n = localScore.length;
  final backlink = Int32List(n)..fillRange(0, n, -1);
  final cumscore = Float64List(n);

  final windowStart = -(2 * period).round();
  final windowEnd = -(period / 2).round();
  if (windowEnd <= windowStart) return const [];

  final windowSize = windowEnd - windowStart + 1;
  final txcost = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    final offset = windowStart + i;
    txcost[i] = -_dpTightness * math.pow(math.log(-offset / period), 2);
  }

  // Seeding: everything before the first plausible beat scores itself, so the
  // tracker can start anywhere in the opening bar rather than being forced to
  // begin at frame 0.
  final firstBeatLimit = math.min(n, (period).round());
  var scoreThreshold = 0.0;
  for (var i = 0; i < firstBeatLimit; i++) {
    if (localScore[i] > scoreThreshold) scoreThreshold = localScore[i];
  }
  scoreThreshold *= 0.01;

  for (var i = 0; i < n; i++) {
    var bestScore = double.negativeInfinity;
    var bestIndex = -1;

    for (var w = 0; w < windowSize; w++) {
      final candidate = i + windowStart + w;
      if (candidate < 0) continue;
      final score = cumscore[candidate] + txcost[w];
      if (score > bestScore) {
        bestScore = score;
        bestIndex = candidate;
      }
    }

    if (bestIndex < 0) {
      cumscore[i] = localScore[i] > scoreThreshold ? localScore[i] : 0;
      backlink[i] = -1;
    } else {
      cumscore[i] = localScore[i] + bestScore;
      backlink[i] = bestIndex;
    }
  }

  final last = _lastBeat(cumscore);
  if (last < 0) return const [];

  final beats = <int>[];
  var cursor = last;
  while (cursor >= 0) {
    beats.add(cursor);
    cursor = backlink[cursor];
  }
  final ordered = beats.reversed.toList();

  return _trimWeakEdges(ordered, localScore);
}

/// Picks where to start the backtrace: the last cumulative-score local maximum
/// that is still competitive with the track as a whole. Taking the global
/// argmax instead would routinely truncate the final bars.
int _lastBeat(Float64List cumscore) {
  final maxima = <double>[];
  for (var i = 1; i < cumscore.length - 1; i++) {
    if (cumscore[i] > cumscore[i - 1] && cumscore[i] >= cumscore[i + 1]) {
      maxima.add(cumscore[i]);
    }
  }
  if (maxima.isEmpty) return -1;

  maxima.sort();
  final median = maxima[maxima.length ~/ 2];
  final threshold = 0.5 * median;

  for (var i = cumscore.length - 2; i >= 1; i--) {
    if (cumscore[i] > cumscore[i - 1] &&
        cumscore[i] >= cumscore[i + 1] &&
        cumscore[i] >= threshold) {
      return i;
    }
  }
  return -1;
}

/// Drops leading and trailing beats that fall on near-silence — the DP happily
/// extrapolates a pulse into a fade-in or run-out where there is no music.
List<int> _trimWeakEdges(List<int> beats, Float32List localScore) {
  if (beats.isEmpty) return beats;

  var sum = 0.0;
  for (final b in beats) {
    sum += localScore[b];
  }
  final threshold = 0.1 * (sum / beats.length);

  var start = 0;
  while (start < beats.length && localScore[beats[start]] < threshold) {
    start++;
  }
  var end = beats.length;
  while (end > start && localScore[beats[end - 1]] < threshold) {
    end--;
  }
  return beats.sublist(start, end);
}

/// Sub-frame peak position by parabolic interpolation over the neighbours.
double _refinePeak(Float32List signal, int index) {
  if (index <= 0 || index >= signal.length - 1) return index.toDouble();
  final left = signal[index - 1];
  final centre = signal[index];
  final right = signal[index + 1];
  final denominator = left - 2 * centre + right;
  if (denominator.abs() < 1e-12) return index.toDouble();
  final delta = 0.5 * (left - right) / denominator;
  if (delta.abs() > 0.5) return index.toDouble();
  return index + delta;
}

/// Per-beat salience in 0..1, scaled against the 90th percentile so a track's
/// own loudest beats read as 1.0 regardless of mastering level.
Float32List _beatStrengths(Float32List onset, List<int> beats) {
  final raw = Float32List(beats.length);
  for (var i = 0; i < beats.length; i++) {
    raw[i] = onset[beats[i]];
  }

  final sorted = raw.toList()..sort();
  final reference = sorted.isEmpty
      ? 0.0
      : sorted[math.min(sorted.length - 1, (sorted.length * 0.9).floor())];
  if (reference <= 0) {
    return Float32List(beats.length)..fillRange(0, beats.length, 0.5);
  }

  for (var i = 0; i < raw.length; i++) {
    raw[i] = clamp01(raw[i] / reference);
  }
  return raw;
}

/// Guesses which beats are downbeats by finding the 4-beat phase whose members
/// are consistently the strongest. Crude — it assumes 4/4 — but right far more
/// often than not, and it only drives how hard the visuals punch.
Uint8List _findDownbeats(Float32List strength) {
  final flags = Uint8List(strength.length);
  if (strength.length < 8) return flags;

  var bestPhase = 0;
  var bestScore = double.negativeInfinity;
  for (var phase = 0; phase < 4; phase++) {
    var score = 0.0;
    for (var i = phase; i < strength.length; i += 4) {
      score += strength[i];
    }
    if (score > bestScore) {
      bestScore = score;
      bestPhase = phase;
    }
  }

  for (var i = bestPhase; i < strength.length; i += 4) {
    flags[i] = 1;
  }
  return flags;
}

/// Tempo from the median inter-beat interval, which tracks the actual grid
/// better than the autocorrelation estimate when a track drifts.
double _bpmFromBeats(Int32List beatsMs, double periodFrames, int sampleRate) {
  if (beatsMs.length < 2) {
    return 60 * sampleRate / (periodFrames * analysisHopSize);
  }
  final intervals = <int>[];
  for (var i = 1; i < beatsMs.length; i++) {
    intervals.add(beatsMs[i] - beatsMs[i - 1]);
  }
  intervals.sort();
  final median = intervals[intervals.length ~/ 2];
  if (median <= 0) return 0;
  return 60000 / median;
}

/// Smooths, normalises and resamples the four band envelopes onto
/// [BeatMap.bandFps], packed interleaved as bytes.
Uint8List _packBands(List<Float32List> bands, int frameCount, int sampleRate) {
  final bandCount = BeatBand.values.length;
  final smoothed = List.generate(bandCount, (b) {
    final source = bands[b];
    final out = Float32List(frameCount);
    var level = 0.0;
    for (var i = 0; i < frameCount; i++) {
      final value = source[i];
      // Asymmetric one-pole: rises quickly so a hit registers, falls slowly so
      // the motion it drives glides instead of snapping back.
      final coefficient = value > level ? 0.5 : 0.12;
      level += (value - level) * coefficient;
      out[i] = level;
    }
    return out;
  }, growable: false);

  final references = List.generate(bandCount, (b) {
    final sorted = smoothed[b].toList()..sort();
    final index = math.min(sorted.length - 1, (sorted.length * 0.99).floor());
    return sorted.isEmpty ? 0.0 : sorted[index];
  }, growable: false);

  final durationSec = frameCount * analysisHopSize / sampleRate;
  final outFrames = math.max(1, (durationSec * BeatMap.bandFps).floor());
  final packed = Uint8List(outFrames * bandCount);

  for (var frame = 0; frame < outFrames; frame++) {
    final sourcePosition = frame / BeatMap.bandFps * analysisFps;
    final lower = sourcePosition.floor().clamp(0, frameCount - 1);
    final upper = math.min(lower + 1, frameCount - 1);
    final fraction = sourcePosition - lower;

    for (var b = 0; b < bandCount; b++) {
      final reference = references[b];
      if (reference <= 0) continue;
      final a = smoothed[b][lower];
      final c = smoothed[b][upper];
      final value = (a + (c - a) * fraction) / reference;
      packed[frame * bandCount + b] = (clamp01(value) * 255).round();
    }
  }

  return packed;
}

Float64List _hannWindow(int size) {
  final window = Float64List(size);
  for (var i = 0; i < size; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / size);
  }
  return window;
}

/// Log-spaced band edges as bin indices, with each band guaranteed at least one
/// bin so the low end doesn't collapse to empty ranges.
Int32List _logBandEdges(int count, double lowHz, double highHz, int binCount) {
  final edges = Int32List(count + 1);
  final binWidth = analysisSampleRate / analysisFftSize;
  final logLow = math.log(lowHz);
  final logHigh = math.log(highHz);

  for (var i = 0; i <= count; i++) {
    final hz = math.exp(logLow + (logHigh - logLow) * i / count);
    var bin = (hz / binWidth).round();
    if (i > 0 && bin <= edges[i - 1]) bin = edges[i - 1] + 1;
    edges[i] = math.min(bin, binCount);
  }
  return edges;
}

Int32List _fixedBandEdges(List<double> edgesHz, int binCount) {
  final binWidth = analysisSampleRate / analysisFftSize;
  final edges = Int32List(edgesHz.length);
  for (var i = 0; i < edgesHz.length; i++) {
    var bin = (edgesHz[i] / binWidth).round();
    if (i > 0 && bin <= edges[i - 1]) bin = edges[i - 1] + 1;
    edges[i] = math.min(bin, binCount);
  }
  return edges;
}

/// In-place iterative radix-2 Cooley–Tukey FFT.
///
/// Twiddle factors and the bit-reversal permutation are computed once and
/// reused across every frame — rebuilding them per frame is what makes naive
/// Dart FFT implementations unusably slow over a full track.
class _Fft {
  final int size;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _reversed;

  _Fft(this.size)
      : _cos = Float64List(size ~/ 2),
        _sin = Float64List(size ~/ 2),
        _reversed = Int32List(size) {
    assert(
        size > 0 && (size & (size - 1)) == 0, 'FFT size must be a power of 2');

    for (var i = 0; i < size ~/ 2; i++) {
      final angle = -2 * math.pi * i / size;
      _cos[i] = math.cos(angle);
      _sin[i] = math.sin(angle);
    }

    final bits = size.bitLength - 1;
    for (var i = 0; i < size; i++) {
      var value = i;
      var reversed = 0;
      for (var b = 0; b < bits; b++) {
        reversed = (reversed << 1) | (value & 1);
        value >>= 1;
      }
      _reversed[i] = reversed;
    }
  }

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < size; i++) {
      final j = _reversed[i];
      if (j > i) {
        var temp = re[i];
        re[i] = re[j];
        re[j] = temp;
        temp = im[i];
        im[i] = im[j];
        im[j] = temp;
      }
    }

    for (var length = 2; length <= size; length <<= 1) {
      final half = length >> 1;
      final step = size ~/ length;
      for (var start = 0; start < size; start += length) {
        var twiddle = 0;
        for (var offset = 0; offset < half; offset++) {
          final wr = _cos[twiddle];
          final wi = _sin[twiddle];
          final top = start + offset;
          final bottom = top + half;

          final vr = re[bottom] * wr - im[bottom] * wi;
          final vi = re[bottom] * wi + im[bottom] * wr;
          final ur = re[top];
          final ui = im[top];

          re[top] = ur + vr;
          im[top] = ui + vi;
          re[bottom] = ur - vr;
          im[bottom] = ui - vi;

          twiddle += step;
        }
      }
    }
  }
}

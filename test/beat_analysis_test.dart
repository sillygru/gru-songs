import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/beat_map.dart';
import 'package:wispie/domain/services/beat_analysis.dart';

/// Synthesises a click track at [bpm] lasting [seconds].
///
/// Each click is a decaying low sine (a kick) plus a short broadband noise
/// burst (the transient) — enough spectral structure that the analyser is
/// exercised the way real percussion exercises it, rather than being handed
/// mathematically perfect impulses.
Float32List clickTrack({
  required double bpm,
  required double seconds,
  int sampleRate = analysisSampleRate,
  double accentEvery = 0,

  /// Clicks whose start falls inside this window (seconds) are omitted.
  List<double>? silentRange,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final samples = Float32List((seconds * sampleRate).round());
  final interval = 60.0 / bpm;

  var index = 0;
  for (var time = 0.0; time < seconds; time += interval, index++) {
    if (silentRange != null &&
        time >= silentRange[0] &&
        time < silentRange[1]) {
      continue;
    }

    var amplitude = 0.6;
    if (accentEvery > 0 && index % accentEvery.round() == 0) amplitude *= 1.7;

    final start = (time * sampleRate).round();
    final kickLength = (0.15 * sampleRate).round();
    for (var i = 0; i < kickLength; i++) {
      final position = start + i;
      if (position >= samples.length) break;
      final t = i / sampleRate;
      samples[position] +=
          amplitude * math.sin(2 * math.pi * 55 * t) * math.exp(-t * 25);
    }

    final noiseLength = (0.05 * sampleRate).round();
    for (var i = 0; i < noiseLength; i++) {
      final position = start + i;
      if (position >= samples.length) break;
      final t = i / sampleRate;
      samples[position] +=
          amplitude * 0.35 * (random.nextDouble() * 2 - 1) * math.exp(-t * 80);
    }
  }

  return samples;
}

/// True click times in milliseconds, for the same parameters.
List<int> expectedClicksMs({
  required double bpm,
  required double seconds,
  List<double>? silentRange,
}) {
  final interval = 60.0 / bpm;
  final clicks = <int>[];
  for (var time = 0.0; time < seconds; time += interval) {
    if (silentRange != null &&
        time >= silentRange[0] &&
        time < silentRange[1]) {
      continue;
    }
    clicks.add((time * 1000).round());
  }
  return clicks;
}

/// Signed distance from [beatMs] to the nearest entry in [clicks].
int nearestOffsetMs(int beatMs, List<int> clicks) {
  var best = clicks.first - beatMs;
  for (final click in clicks) {
    final delta = click - beatMs;
    if (delta.abs() < best.abs()) best = delta;
  }
  return best;
}

void main() {
  group('tempo estimation', () {
    // The tempo prior exists to stop the autocorrelation collapsing to half or
    // double time. These three tempi straddle its 120 BPM centre, so a broken
    // prior shows up as one of them landing on 2x or 0.5x.
    for (final bpm in [75.0, 120.0, 160.0]) {
      test('locks onto $bpm BPM', () {
        final map = analyzeBeats(clickTrack(bpm: bpm, seconds: 20));

        expect(map.hasBeats, isTrue);
        expect(map.bpm, closeTo(bpm, 2.0));
      });
    }
  });

  group('beat placement', () {
    test('every detected beat lands on a real click', () {
      const bpm = 120.0;
      const seconds = 20.0;
      final map = analyzeBeats(clickTrack(bpm: bpm, seconds: seconds));
      final clicks = expectedClicksMs(bpm: bpm, seconds: seconds);

      final offsets = [
        for (final beat in map.beatsMs) nearestOffsetMs(beat, clicks),
      ];
      final worst = offsets.map((o) => o.abs()).reduce(math.max);

      expect(
        worst,
        lessThanOrEqualTo(25),
        reason: 'beats drifted off the click grid by ${worst}ms',
      );
    });

    test('finds close to every beat in the track', () {
      const bpm = 120.0;
      const seconds = 20.0;
      final map = analyzeBeats(clickTrack(bpm: bpm, seconds: seconds));
      final clicks = expectedClicksMs(bpm: bpm, seconds: seconds);

      // Edge trimming legitimately drops a beat or two at each end.
      expect(map.beatsMs.length, greaterThanOrEqualTo(clicks.length - 3));
      expect(map.beatsMs.length, lessThanOrEqualTo(clicks.length + 1));
    });

    test('beat times are strictly ascending', () {
      final map = analyzeBeats(clickTrack(bpm: 128, seconds: 15));
      for (var i = 1; i < map.beatsMs.length; i++) {
        expect(map.beatsMs[i], greaterThan(map.beatsMs[i - 1]));
      }
    });
  });

  // The whole reason this pipeline does tempo inference and dynamic programming
  // rather than thresholding an energy envelope. A listener keeps tapping
  // through a silent bar; a threshold detector cannot, because there is nothing
  // to threshold. If this test fails the feature has regressed to what was
  // removed in 4500090.
  test('pulse continues through four silent bars', () {
    const bpm = 120.0;
    const seconds = 24.0;
    // 8s..16s is silent — eight seconds at 120 BPM is sixteen missing beats.
    const silence = [8.0, 16.0];

    final map = analyzeBeats(
      clickTrack(bpm: bpm, seconds: seconds, silentRange: silence),
    );

    final duringSilence =
        map.beatsMs.where((ms) => ms > 8500 && ms < 15500).toList();

    expect(
      duringSilence.length,
      greaterThanOrEqualTo(12),
      reason:
          'the beat grid stopped during silence instead of carrying through',
    );

    // And it must come back in phase on the other side, not drifted.
    final clicks = expectedClicksMs(
      bpm: bpm,
      seconds: seconds,
      silentRange: silence,
    );
    final afterSilence = map.beatsMs.where((ms) => ms > 16500);
    for (final beat in afterSilence) {
      expect(
        nearestOffsetMs(beat, clicks).abs(),
        lessThanOrEqualTo(30),
        reason: 'phase was lost across the silent stretch',
      );
    }
  });

  group('downbeats', () {
    test('picks the accented phase', () {
      final map = analyzeBeats(
        clickTrack(bpm: 120, seconds: 24, accentEvery: 4),
      );

      final downbeatIndices = <int>[];
      for (var i = 0; i < map.downbeats.length; i++) {
        if (map.downbeats[i] == 1) downbeatIndices.add(i);
      }

      expect(downbeatIndices, isNotEmpty);
      // Whatever phase is chosen, downbeats must be a strict every-fourth grid.
      for (var i = 1; i < downbeatIndices.length; i++) {
        expect(downbeatIndices[i] - downbeatIndices[i - 1], 4);
      }

      // The accented beats should be measurably stronger than the rest.
      var accented = 0.0;
      var others = 0.0;
      var accentedCount = 0;
      var otherCount = 0;
      for (var i = 0; i < map.beatStrength.length; i++) {
        if (map.downbeats[i] == 1) {
          accented += map.beatStrength[i];
          accentedCount++;
        } else {
          others += map.beatStrength[i];
          otherCount++;
        }
      }
      expect(accentedCount, greaterThan(0));
      expect(otherCount, greaterThan(0));
      expect(accented / accentedCount, greaterThan(others / otherCount));
    });
  });

  group('degenerate input', () {
    test('silence yields an empty map rather than phantom beats', () {
      final map = analyzeBeats(Float32List(analysisSampleRate * 10));

      expect(map.hasBeats, isFalse);
      expect(map.bpm, 0);
      expect(map.durationMs, closeTo(10000, 50));
    });

    test('a sub-second buffer is handled without throwing', () {
      final map = analyzeBeats(Float32List(analysisSampleRate ~/ 4));

      expect(map.hasBeats, isFalse);
    });

    test('an empty buffer is handled without throwing', () {
      expect(analyzeBeats(Float32List(0)).hasBeats, isFalse);
    });

    // The onset envelope is standard-deviation normalised, so without a gate on
    // the raw signal these two would have their noise floor amplified into a
    // confident, entirely fictional pulse.
    test('a pure sustained tone produces no beat grid', () {
      final samples = Float32List(analysisSampleRate * 8);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = 0.5 * math.sin(2 * math.pi * 440 * i / analysisSampleRate);
      }

      expect(analyzeBeats(samples).hasBeats, isFalse);
    });

    test('a beatless pad gets no pulse but keeps its band envelopes', () {
      final samples = Float32List(analysisSampleRate * 16);
      for (var i = 0; i < samples.length; i++) {
        final t = i / analysisSampleRate;
        final swell = 0.3 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.08 * t));
        samples[i] = swell *
            (math.sin(2 * math.pi * 220 * t) +
                0.6 * math.sin(2 * math.pi * 330 * t));
      }

      final map = analyzeBeats(samples);

      expect(map.hasBeats, isFalse);
      // Ambient still has to feel alive: the render layer falls back to
      // breathing on these, so they must not come back empty.
      expect(map.bandFrameCount, greaterThan(0));
      var total = 0.0;
      for (var frame = 0; frame < map.bandFrameCount; frame++) {
        total += map.bandAt(BeatBand.lowMid, frame / BeatMap.bandFps * 1000);
      }
      expect(total, greaterThan(0));
    });

    test('quiet percussive material still gets a beat grid', () {
      // 2% amplitude — far below any real mastering level. The percussive gate
      // must key on transient structure, not loudness.
      final quiet = Float32List.fromList(
        clickTrack(bpm: 120, seconds: 16).map((s) => s * 0.02).toList(),
      );

      expect(analyzeBeats(quiet).hasBeats, isTrue);
    });
  });

  group('band envelopes', () {
    test('a kick track puts its energy in the bass band', () {
      final map = analyzeBeats(clickTrack(bpm: 120, seconds: 16));

      var bass = 0.0;
      var air = 0.0;
      for (var frame = 0; frame < map.bandFrameCount; frame++) {
        final ms = frame / BeatMap.bandFps * 1000;
        bass += map.bandAt(BeatBand.bass, ms);
        air += map.bandAt(BeatBand.air, ms);
      }

      expect(map.bandFrameCount, greaterThan(0));
      expect(bass, greaterThan(air));
    });

    test('band lookups are clamped outside the track', () {
      final map = analyzeBeats(clickTrack(bpm: 120, seconds: 16));

      expect(map.bandAt(BeatBand.bass, -500), inInclusiveRange(0.0, 1.0));
      expect(map.bandAt(BeatBand.bass, 1e9), inInclusiveRange(0.0, 1.0));
    });
  });

  group('BeatMap', () {
    test('survives a JSON round trip', () {
      final map = analyzeBeats(clickTrack(bpm: 128, seconds: 16));
      final restored = BeatMap.fromJson(map.toJson());

      expect(restored, isNotNull);
      expect(restored!.beatsMs, map.beatsMs);
      expect(restored.downbeats, map.downbeats);
      expect(restored.bands, map.bands);
      expect(restored.bpm, closeTo(map.bpm, 0.001));
      for (var i = 0; i < map.beatStrength.length; i++) {
        expect(restored.beatStrength[i], closeTo(map.beatStrength[i], 0.01));
      }
    });

    test('rejects a payload from a different algorithm version', () {
      final json = analyzeBeats(clickTrack(bpm: 120, seconds: 16)).toJson();
      json['v'] = BeatMap.currentVersion + 1;

      expect(BeatMap.fromJson(json), isNull);
    });

    test('rejects a truncated payload', () {
      final json = analyzeBeats(clickTrack(bpm: 120, seconds: 16)).toJson();
      json['beats'] = [1, 2, 3];

      expect(BeatMap.fromJson(json), isNull);
    });

    test('beatIndexAt binary search agrees with a linear scan', () {
      final map = analyzeBeats(clickTrack(bpm: 120, seconds: 16));
      expect(map.hasBeats, isTrue);

      for (var ms = 0; ms < map.durationMs; ms += 97) {
        var expected = -1;
        for (var i = 0; i < map.beatsMs.length; i++) {
          if (map.beatsMs[i] <= ms) expected = i;
        }
        expect(map.beatIndexAt(ms), expected, reason: 'at ${ms}ms');
      }
    });
  });
}

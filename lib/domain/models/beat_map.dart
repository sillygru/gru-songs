import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Frequency bands the analyser tracks, in order. The index into a [BeatMap]'s
/// interleaved band data is the enum index.
enum BeatBand {
  /// 20–150 Hz. Kick drums and bass — what people actually feel as "the beat".
  bass,

  /// 150–800 Hz. Body of most instruments.
  lowMid,

  /// 800–4000 Hz. Vocals and presence.
  mid,

  /// 4000–11025 Hz. Hats, cymbals, air.
  air,
}

/// The precomputed rhythmic description of one song.
///
/// Produced offline by `analyzeBeats` and cached to disk, then replayed against
/// the playhead at render time. Nothing here is computed during playback — that
/// is the whole point of the format.
class BeatMap {
  /// Bumped whenever the analysis algorithm changes in a way that makes old
  /// cached maps wrong. [fromJson] rejects anything that does not match, so a
  /// bump silently re-analyses everyone's library instead of showing stale data.
  static const int currentVersion = 1;

  /// Rate at which [bands] is sampled. Envelopes are interpolated between
  /// samples at render time, so this can stay well below the display refresh.
  static const double bandFps = 30;

  final int version;
  final int durationMs;

  /// Estimated tempo. Informational — the beat grid is authoritative, since a
  /// track that drifts or changes tempo still gets correct beats.
  final double bpm;

  /// Beat times in milliseconds from the start of the track, ascending.
  final Int32List beatsMs;

  /// Per-beat salience in 0..1, parallel to [beatsMs].
  final Float32List beatStrength;

  /// Whether each beat is a downbeat (the "1" of a bar), parallel to [beatsMs].
  final Uint8List downbeats;

  /// Band energy envelopes in 0..255, interleaved by frame:
  /// `bands[frame * BeatBand.values.length + band.index]`.
  final Uint8List bands;

  const BeatMap({
    required this.version,
    required this.durationMs,
    required this.bpm,
    required this.beatsMs,
    required this.beatStrength,
    required this.downbeats,
    required this.bands,
  });

  /// A map with no rhythmic content — used for silence, undecodable audio and
  /// clips too short to analyse. Consumers fall back to idle motion.
  factory BeatMap.empty({int durationMs = 0}) {
    return BeatMap(
      version: currentVersion,
      durationMs: durationMs,
      bpm: 0,
      beatsMs: Int32List(0),
      beatStrength: Float32List(0),
      downbeats: Uint8List(0),
      bands: Uint8List(0),
    );
  }

  bool get hasBeats => beatsMs.isNotEmpty;

  int get bandFrameCount => bands.length ~/ BeatBand.values.length;

  /// Index of the last beat at or before [positionMs], or -1 if the position is
  /// before the first beat.
  ///
  /// Binary search: this runs once per rendered frame, and a linear scan over a
  /// six-minute track's ~800 beats would be wasted work sixty times a second.
  int beatIndexAt(int positionMs) {
    if (beatsMs.isEmpty || positionMs < beatsMs[0]) return -1;

    var low = 0;
    var high = beatsMs.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (beatsMs[mid] <= positionMs) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// Linearly interpolated energy of [band] at [positionMs], in 0..1.
  double bandAt(BeatBand band, double positionMs) {
    final frameCount = bandFrameCount;
    if (frameCount == 0) return 0;

    final exact = positionMs / 1000 * bandFps;
    if (exact <= 0) return bands[band.index] / 255;

    final lower = exact.floor();
    if (lower >= frameCount - 1) {
      final last = (frameCount - 1) * BeatBand.values.length + band.index;
      return bands[last] / 255;
    }

    final stride = BeatBand.values.length;
    final a = bands[lower * stride + band.index] / 255;
    final b = bands[(lower + 1) * stride + band.index] / 255;
    return a + (b - a) * (exact - lower);
  }

  /// The interval between beats around [index], in milliseconds.
  ///
  /// Falls back to the neighbouring interval at the ends and to [bpm] for a
  /// single-beat map, so callers never have to special-case the edges.
  double beatPeriodMsAt(int index) {
    if (beatsMs.length < 2) return bpm > 0 ? 60000 / bpm : 500;
    final i = index.clamp(0, beatsMs.length - 2);
    return (beatsMs[i + 1] - beatsMs[i]).toDouble();
  }

  Map<String, dynamic> toJson() {
    return {
      'v': version,
      'durationMs': durationMs,
      'bpm': bpm,
      'beats': beatsMs.toList(),
      // Strength is only ever read as a visual amplitude, so a byte per beat is
      // plenty and keeps the cache small.
      'strength': base64Encode(
        Uint8List.fromList([
          for (final s in beatStrength) (s.clamp(0.0, 1.0) * 255).round(),
        ]),
      ),
      'downbeats': base64Encode(downbeats),
      'bands': base64Encode(bands),
      'bandFps': bandFps,
    };
  }

  /// Returns null when the payload is missing, malformed, or was written by a
  /// different algorithm version. Callers treat null as a cache miss.
  static BeatMap? fromJson(Map<String, dynamic> json) {
    try {
      if (json['v'] != currentVersion) return null;
      if (json['bandFps'] != bandFps) return null;

      final rawStrength = base64Decode(json['strength'] as String);
      final beats = Int32List.fromList(
        (json['beats'] as List).cast<num>().map((n) => n.toInt()).toList(),
      );
      if (rawStrength.length != beats.length) return null;

      final downbeats = base64Decode(json['downbeats'] as String);
      if (downbeats.length != beats.length) return null;

      final bands = base64Decode(json['bands'] as String);
      if (bands.length % BeatBand.values.length != 0) return null;

      return BeatMap(
        version: json['v'] as int,
        durationMs: (json['durationMs'] as num).toInt(),
        bpm: (json['bpm'] as num).toDouble(),
        beatsMs: beats,
        beatStrength: Float32List.fromList(
          [for (final b in rawStrength) b / 255],
        ),
        downbeats: downbeats,
        bands: bands,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Clamps [value] into 0..1. Shared by the analyser and the render layer so the
/// two agree on what "normalised" means.
double clamp01(double value) {
  if (value.isNaN) return 0;
  return math.max(0, math.min(1, value));
}

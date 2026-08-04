import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/waveform_service.dart';

void main() {
  group('extractWaveformPeaksFromS16Bytes', () {
    test('buckets full PCM into exactly the requested bar count', () {
      final peaks = extractWaveformPeaksFromS16Bytes(_pcmBytes(20000), 2000);

      expect(peaks.length, 2000);
      for (final peak in peaks) {
        expect(peak, inInclusiveRange(0.0, 1.0));
      }
      expect(peaks.any((p) => p > 0.1), isTrue,
          reason: 'a non-silent buffer must yield visible bars');
    });

    test('returns placeholders for fewer than two bytes', () {
      final peaks = extractWaveformPeaksFromS16Bytes(Uint8List(1), 2000);

      expect(peaks.length, 2000);
      for (final peak in peaks) {
        expect(peak, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('progressiveWaveformPeaksFromS16Bytes', () {
    final fullBytes = _pcmBytes(40000); // 40000 samples -> 80000 bytes

    test('a quarter-decoded buffer fills a quarter of the bars', () {
      final quarter = fullBytes.sublist(0, 20000);
      final peaks = progressiveWaveformPeaksFromS16Bytes(
        quarter,
        2000,
        fullBytes.length,
      );

      expect(peaks.length, 500);
      for (final peak in peaks) {
        expect(peak, inInclusiveRange(0.0, 1.0));
      }
    });

    test('half-decoded buffer fills half of the bars', () {
      final half = fullBytes.sublist(0, 40000);
      final peaks = progressiveWaveformPeaksFromS16Bytes(
        half,
        2000,
        fullBytes.length,
      );

      expect(peaks.length, 1000);
    });

    test('a complete buffer fills the whole bar count', () {
      final peaks = progressiveWaveformPeaksFromS16Bytes(
        fullBytes,
        2000,
        fullBytes.length,
      );

      expect(peaks.length, WaveformService.targetWaveformSamples);
    });

    test('unknown expected size falls back to the full bar count', () {
      final peaks = progressiveWaveformPeaksFromS16Bytes(
        fullBytes.sublist(0, 40000),
        2000,
        0,
      );

      expect(peaks.length, 2000);
    });
  });
}

/// Produces little-endian s16le PCM bytes: a sine with noise so the peaks are
/// not uniform.
Uint8List _pcmBytes(int sampleCount, {double amplitude = 0.8}) {
  final data = ByteData(sampleCount * 2);
  final random = math.Random(42);
  for (var i = 0; i < sampleCount; i++) {
    final sine = math.sin(i * 0.05) * amplitude * 0.6;
    final noise = (random.nextDouble() - 0.5) * amplitude;
    final v = (sine + noise).clamp(-1.0, 1.0) * 32767;
    data.setInt16(i * 2, v.round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

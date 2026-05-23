import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/audio_energy_analyzer.dart';

void main() {
  group('sampleEnergyAtPosition', () {
    test('returns peak near playhead', () {
      final waveform = List<double>.generate(100, (i) => i / 100);
      final energy = sampleEnergyAtPosition(
        waveform: waveform,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );
      expect(energy, closeTo(0.5, 0.08));
    });

    test('returns zero for empty waveform', () {
      expect(
        sampleEnergyAtPosition(
          waveform: const [],
          position: Duration.zero,
          duration: const Duration(seconds: 10),
        ),
        0,
      );
    });
  });

  group('detectBeatPulse', () {
    test('detects spike above baseline', () {
      final history = Queue<double>.from([0.1, 0.12, 0.11, 0.1, 0.12, 0.11]);
      final beat = detectBeatPulse(
        rawEnergy: 0.35,
        baseline: 0.1,
        history: history,
        historySize: 14,
        beatMultiplier: 1.10,
      );
      expect(beat, isTrue);
    });

    test('ignores low energy below floor', () {
      final history = Queue<double>.from([0.02, 0.03, 0.02, 0.03, 0.02, 0.03]);
      final beat = detectBeatPulse(
        rawEnergy: 0.05,
        baseline: 0.03,
        history: history,
        historySize: 14,
        beatMultiplier: 1.10,
      );
      expect(beat, isFalse);
    });

    test('steady beat still triggers when above baseline', () {
      // Simulates "boom boom boom" — raw energy is consistently high
      // but baseline lags behind, so beats still fire
      final history = Queue<double>();
      // Pre-fill so the length check passes
      for (var i = 0; i < 4; i++) {
        history.add(28);
      }
      expect(
        detectBeatPulse(
          rawEnergy: 30,
          baseline: 26,
          history: history,
          historySize: 14,
          beatMultiplier: 1.10,
        ),
        isTrue,
      );
    });

    test('no beat when raw is close to baseline', () {
      final history = Queue<double>();
      for (var i = 0; i < 6; i++) {
        history.add(30);
      }
      expect(
        detectBeatPulse(
          rawEnergy: 30,
          baseline: 29,
          history: history,
          historySize: 14,
          beatMultiplier: 1.10,
        ),
        isFalse,
      );
    });
  });
}

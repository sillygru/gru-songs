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
    test('detects spike above rolling average', () {
      final history = Queue<double>.from([0.1, 0.12, 0.11, 0.1, 0.12, 0.11]);
      final beat = detectBeatPulse(
        rawEnergy: 0.35,
        history: history,
        historySize: 14,
        beatMultiplier: 1.28,
        beatFloor: 0.12,
      );
      expect(beat, isTrue);
    });

    test('ignores low energy below floor', () {
      final history = Queue<double>.from([0.02, 0.03, 0.02, 0.03, 0.02, 0.03]);
      final beat = detectBeatPulse(
        rawEnergy: 0.05,
        history: history,
        historySize: 14,
        beatMultiplier: 1.28,
        beatFloor: 0.12,
      );
      expect(beat, isFalse);
    });
  });
}

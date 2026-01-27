import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/providers/settings_provider.dart';

void main() {
  group('Volume Settings Tests', () {
    test('Should have correct default values', () {
      final state = SettingsState();
      expect(state.autoPauseOnVolumeZero, true);
      expect(state.autoResumeOnVolumeRestore, true);
    });

    test('Should copy with new values', () {
      final state = SettingsState();

      final updatedState = state.copyWith(
        autoPauseOnVolumeZero: false,
        autoResumeOnVolumeRestore: false,
      );

      expect(updatedState.autoPauseOnVolumeZero, false);
      expect(updatedState.autoResumeOnVolumeRestore, false);
      expect(updatedState.visualizerEnabled, true); // Should remain unchanged
      expect(updatedState.telemetryLevel, 1); // Should remain unchanged
    });

    test('Should handle independent setting changes', () {
      final state = SettingsState();

      // Change only auto-pause
      final state1 = state.copyWith(autoPauseOnVolumeZero: false);
      expect(state1.autoPauseOnVolumeZero, false);
      expect(state1.autoResumeOnVolumeRestore, true);

      // Change only auto-resume
      final state2 = state.copyWith(autoResumeOnVolumeRestore: false);
      expect(state2.autoPauseOnVolumeZero, true);
      expect(state2.autoResumeOnVolumeRestore, false);

      // Change both
      final state3 = state.copyWith(
        autoPauseOnVolumeZero: false,
        autoResumeOnVolumeRestore: false,
      );
      expect(state3.autoPauseOnVolumeZero, false);
      expect(state3.autoResumeOnVolumeRestore, false);
    });
  });
}

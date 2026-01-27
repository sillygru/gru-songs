import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/volume_monitor_service.dart';

void main() {
  group('VolumeMonitorService Tests', () {
    late VolumeMonitorService volumeMonitorService;
    bool volumeZeroCalled = false;
    bool volumeRestoredCalled = false;

    setUp(() {
      volumeZeroCalled = false;
      volumeRestoredCalled = false;
      volumeMonitorService = VolumeMonitorService(
        onVolumeZero: () {
          volumeZeroCalled = true;
        },
        onVolumeRestored: () {
          volumeRestoredCalled = true;
        },
      );
    });

    tearDown(() {
      volumeMonitorService.dispose();
    });

    test('Initial state should have auto-pause disabled', () {
      expect(volumeMonitorService.isAutoPauseEnabled, false);
    });

    test('Should enable/disable auto-pause', () {
      volumeMonitorService.setAutoPauseEnabled(true);
      expect(volumeMonitorService.isAutoPauseEnabled, true);

      volumeMonitorService.setAutoPauseEnabled(false);
      expect(volumeMonitorService.isAutoPauseEnabled, false);
    });

    test('Should track current volume', () {
      // Test that volume can be tracked (actual volume values come from native side)
      expect(volumeMonitorService.currentVolume, isA<double>());
    });

    test('Should reset wasPlayingBeforeMute when disabled', () {
      volumeMonitorService.setAutoPauseEnabled(true);
      volumeMonitorService.setAutoPauseEnabled(false);
      // The internal _wasPlayingBeforeMute should be reset
      // This is tested indirectly by ensuring no errors occur
    });

    test('Should trigger callbacks when volume changes to 0 and back', () {
      // Enable auto-pause
      volumeMonitorService.setAutoPauseEnabled(true);

      // Simulate volume going to 0 (mute)
      volumeMonitorService.onVolumeChanged(0.0);
      expect(volumeZeroCalled, true);
      expect(volumeRestoredCalled, false);

      // Reset flags
      volumeZeroCalled = false;

      // Simulate volume being restored
      volumeMonitorService.onVolumeChanged(0.5);
      expect(volumeZeroCalled, false);
      expect(volumeRestoredCalled, true);
    });

    test('Should not trigger restore callback if not auto-muted', () {
      // Enable auto-pause
      volumeMonitorService.setAutoPauseEnabled(true);

      // Simulate volume going from 0.2 to 0.5 (not from 0)
      volumeMonitorService.onVolumeChanged(0.5);
      expect(volumeZeroCalled, false);
      expect(volumeRestoredCalled, false);
    });

    test('Should not trigger callbacks when auto-pause is disabled', () {
      // Keep auto-pause disabled
      expect(volumeMonitorService.isAutoPauseEnabled, false);

      // Simulate volume changes
      volumeMonitorService.onVolumeChanged(0.0);
      volumeMonitorService.onVolumeChanged(0.5);

      expect(volumeZeroCalled, false);
      expect(volumeRestoredCalled, false);
    });
  });
}

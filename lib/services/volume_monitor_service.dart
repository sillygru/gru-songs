import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class VolumeMonitorService {
  static const MethodChannel _channel = MethodChannel('gru_songs/volume');
  static const EventChannel _eventChannel =
      EventChannel('gru_songs/volume_events');

  StreamSubscription<double>? _volumeSubscription;
  double _currentVolume = 1.0;
  bool _isAutoPauseEnabled = false;
  bool _wasPlayingBeforeMute = false;

  final VoidCallback? onVolumeZero;
  final VoidCallback? onVolumeRestored;

  VolumeMonitorService({
    this.onVolumeZero,
    this.onVolumeRestored,
  });

  Future<void> initialize() async {
    try {
      _currentVolume =
          await _channel.invokeMethod<double>('getCurrentVolume') ?? 1.0;
      _startVolumeMonitoring();
    } catch (e) {
      debugPrint('Failed to initialize volume monitoring: $e');
    }
  }

  void _startVolumeMonitoring() {
    _volumeSubscription = _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as double)
        .listen(onVolumeChanged);
  }

  void onVolumeChanged(double volume) {
    final previousVolume = _currentVolume;
    _currentVolume = volume;

    if (!_isAutoPauseEnabled) return;

    // Use a small epsilon for floating point comparison
    const epsilon = 1e-6;

    // Check if volume changed to 0 (muted)
    if (previousVolume > epsilon && volume <= epsilon) {
      onVolumeZero?.call();
      _wasPlayingBeforeMute = true;
    }
    // Check if volume restored from 0
    else if (previousVolume <= epsilon &&
        volume > epsilon &&
        _wasPlayingBeforeMute) {
      onVolumeRestored?.call();
      _wasPlayingBeforeMute = false;
    }
  }

  void setAutoPauseEnabled(bool enabled) {
    _isAutoPauseEnabled = enabled;
    if (!enabled) {
      _wasPlayingBeforeMute = false;
    }
  }

  bool get isAutoPauseEnabled => _isAutoPauseEnabled;

  double get currentVolume => _currentVolume;

  void dispose() {
    _volumeSubscription?.cancel();
    _volumeSubscription = null;
  }
}

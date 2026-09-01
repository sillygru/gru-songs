import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the device is in a power-saving state — Android's battery saver or
/// iOS's Low Power Mode.
///
/// This is the OS telling us the user is trying to make the battery last, which
/// is a different signal from the accessibility "remove animations" switch: it
/// comes and goes on its own, and it asks for *less* work rather than none. The
/// player answers it by halving its frame rate and thinning the mote field
/// rather than by turning anything off, so the screen still moves with the
/// music on a phone that is being nursed through the evening.
///
/// Published as a [ValueNotifier] rather than through Riverpod, matching the
/// convention for hot-path state elsewhere: the listeners are painters and one
/// screen, not the provider graph.
///
/// The channel is optional. A platform that doesn't implement it — a desktop
/// build, a test without the mock — leaves this at `false` forever, which is
/// exactly the pre-existing behaviour.
class PowerStateService {
  static const MethodChannel _channel = MethodChannel('wispie/power');
  static const EventChannel _eventChannel = EventChannel('wispie/power_events');
  // Legacy names for backward compat with older installs/tests.
  static const MethodChannel _legacyChannel = MethodChannel('gru_songs/power');
  static const EventChannel _legacyEventChannel =
      EventChannel('gru_songs/power_events');

  static final PowerStateService instance = PowerStateService._();

  PowerStateService._();

  final ValueNotifier<bool> powerSave = ValueNotifier(false);

  StreamSubscription<dynamic>? _subscription;
  bool _started = false;

  /// Reads the current state and subscribes to changes. Safe to call more than
  /// once; safe to never call at all.
  Future<void> initialize() async {
    if (_started) return;
    _started = true;

    try {
      final primary = await _channel.invokeMethod<bool>('isPowerSaveMode');
      if (primary != null) {
        powerSave.value = primary;
      } else {
        // Try legacy channel.
        powerSave.value =
            await _legacyChannel.invokeMethod<bool>('isPowerSaveMode') ?? false;
      }
    } on MissingPluginException {
      // Try legacy channel before giving up.
      try {
        powerSave.value =
            await _legacyChannel.invokeMethod<bool>('isPowerSaveMode') ?? false;
      } on MissingPluginException {
        return;
      } catch (e) {
        debugPrint('PowerStateService: initial read failed: $e');
      }
      // Fall through to event subscription with legacy.
    } catch (e) {
      debugPrint('PowerStateService: initial read failed: $e');
    }

    // Prefer wispie channel, fall back to legacy.
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is bool) powerSave.value = event;
        },
        onError: (Object _) async {
          // Fall back to legacy stream.
          try {
            _subscription = _legacyEventChannel.receiveBroadcastStream().listen(
              (event) {
                if (event is bool) powerSave.value = event;
              },
              onError: (Object e) {
                debugPrint('PowerStateService: legacy event error: $e');
              },
            );
          } catch (e) {
            debugPrint('PowerStateService: failed to subscribe: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('PowerStateService: failed to subscribe: $e');
      // Try legacy directly.
      try {
        _subscription = _legacyEventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is bool) powerSave.value = event;
          },
          onError: (Object err) {
            debugPrint('PowerStateService: legacy event error: $err');
          },
        );
      } catch (_) {}
    }
  }

  @visibleForTesting
  void debugSetPowerSave(bool value) => powerSave.value = value;

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}

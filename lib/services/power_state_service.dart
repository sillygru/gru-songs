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
  static const MethodChannel _channel = MethodChannel('gru_songs/power');
  static const EventChannel _eventChannel =
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
      powerSave.value =
          await _channel.invokeMethod<bool>('isPowerSaveMode') ?? false;
    } on MissingPluginException {
      // No implementation on this platform. Nothing more to do — not even the
      // event subscription, which would fail the same way.
      return;
    } catch (e) {
      debugPrint('PowerStateService: initial read failed: $e');
    }

    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is bool) powerSave.value = event;
        },
        onError: (Object e) {
          debugPrint('PowerStateService: event stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('PowerStateService: failed to subscribe: $e');
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

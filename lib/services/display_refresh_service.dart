import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the display refresh rate hint for the player screen.
///
/// Supports discrete 30/60/90/120 dynamic, locked 60, and LTPO 1-120. This
/// service abstracts the difference:
///
/// * Discrete 30/60/90/120 — votes the exact `Display.Mode` with matching size
///   and `refreshRate`, via `preferredDisplayModeId` / `preferredRefreshRate`.
/// * LTPO 1-120 — votes `setFrameRate(hz, COMPATIBILITY_DEFAULT)` so the driver
///   interpolates without a mode switch.
/// * Locked single mode — no-ops.
///
/// Policy: 120Hz only while scrolling/dragging (boost window 2s), 60Hz while
/// player is foregrounded and playing, 30Hz when paused or power-save.
///
/// The native side may not be implemented (desktop, tests, old builds) — in that
/// case all calls are no-ops and the service still tracks state for tests.
class DisplayRefreshService {
  static const MethodChannel _channel = MethodChannel('wispie/display_refresh');

  static final DisplayRefreshService instance = DisplayRefreshService._();

  DisplayRefreshService._();

  bool _initialized = false;
  double? _currentHint;
  Timer? _boostTimer;
  bool _inPlayer = false;
  bool _playing = false;
  bool _powerSave = false;

  // Cached supported modes for diagnostics (filled lazily, never required).
  List<Map<String, dynamic>>? _supportedModes;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final modes =
          await _channel.invokeMethod<List<dynamic>>('getSupportedModes');
      if (modes != null) {
        _supportedModes = modes.cast<Map<String, dynamic>>();
      }
    } on MissingPluginException {
      // No native side — ignore.
    } catch (_) {}
  }

  List<Map<String, dynamic>>? get debugSupportedModes => _supportedModes;

  void enterPlayer({required bool playing, required bool powerSave}) {
    _inPlayer = true;
    _playing = playing;
    _powerSave = powerSave;
    _applyForState();
  }

  void leavePlayer() {
    _inPlayer = false;
    _boostTimer?.cancel();
    _boostTimer = null;
    _clear();
  }

  void onPlayingChanged(bool playing) {
    _playing = playing;
    if (!_inPlayer) return;
    // Cancel boost if pausing — drop to 30Hz immediately.
    if (!playing) {
      _boostTimer?.cancel();
      _boostTimer = null;
    }
    _applyForState();
  }

  void onPowerSaveChanged(bool powerSave) {
    _powerSave = powerSave;
    if (!_inPlayer) return;
    _applyForState();
  }

  /// Call on any scroll/drag/fling that deserves 120Hz.
  void boost120() {
    if (!_inPlayer) return;
    if (_powerSave) return; // Never boost in power save.
    _setHint(120);
    _boostTimer?.cancel();
    _boostTimer = Timer(const Duration(seconds: 2), () {
      if (!_inPlayer) return;
      _applyForState();
    });
  }

  void _applyForState() {
    if (_powerSave) {
      _setHint(30);
      return;
    }
    if (!_playing) {
      _setHint(30);
      return;
    }
    // Playing and in player — default to 60Hz unless boost window active.
    if (_boostTimer?.isActive ?? false) return;
    _setHint(60);
  }

  void _setHint(double hz) {
    if (_currentHint == hz) return;
    _currentHint = hz;
    _invokeSet(hz);
  }

  void _clear() {
    _currentHint = null;
    _boostTimer?.cancel();
    _boostTimer = null;
    _invokeClear();
  }

  Future<void> _invokeSet(double hz) async {
    try {
      await _channel.invokeMethod('setPreferredRefreshRate', {'hz': hz});
    } on MissingPluginException {
      // No native implementation — ignore (tests, desktop, iOS handled via
      // CADisplayLink range which is set via Info.plist, not this channel).
    } catch (e) {
      debugPrint('DisplayRefreshService: set $hz failed: $e');
    }
  }

  Future<void> _invokeClear() async {
    try {
      await _channel.invokeMethod('clearPreferredRefreshRate');
    } on MissingPluginException {
      // Ignore.
    } catch (e) {
      debugPrint('DisplayRefreshService: clear failed: $e');
    }
  }

  @visibleForTesting
  double? get debugCurrentHint => _currentHint;

  @visibleForTesting
  void debugReset() {
    _inPlayer = false;
    _playing = false;
    _powerSave = false;
    _currentHint = null;
    _boostTimer?.cancel();
    _boostTimer = null;
    _initialized = false;
  }
}

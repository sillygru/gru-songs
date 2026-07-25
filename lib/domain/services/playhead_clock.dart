/// A smoothed, latency-compensated estimate of where the listener currently is
/// in the track.
///
/// `player.position` jitters enough between platform updates to make anything
/// beat-locked visibly stutter, and it describes what the *decoder* has reached
/// rather than what has come out of the speaker. Both problems are solved once,
/// here, so every beat-reactive surface in the app agrees on where "now" is.
///
/// Pure: no audio package, no timers. Callers feed it position updates and the
/// playing flag and ask for [visualPositionMs] whenever they render.
class PlayheadClock {
  /// Beyond this the clock has been seeked or the track changed, so snap
  /// instead of easing.
  static const int snapThresholdMs = 250;

  /// Fraction of the remaining error corrected per position update. Small
  /// enough that ordinary jitter is invisible, large enough to converge in
  /// well under a second.
  static const double easeFactor = 0.15;

  Duration _anchorPosition = Duration.zero;
  int _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
  bool _playing = false;

  PlayheadClock({Duration position = Duration.zero, bool playing = false}) {
    _anchorPosition = position;
    _playing = playing;
  }

  bool get playing => _playing;

  set playing(bool value) {
    if (_playing == value) return;
    // Re-anchor across the transition so the clock does not jump by however
    // long the player sat paused.
    _anchorPosition = predicted;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _playing = value;
  }

  /// Visual offset in milliseconds, compensating audio output latency.
  ///
  /// Wired to a user setting because the correct value is not a property of the
  /// app: wired headphones need ~50 ms while Bluetooth routinely needs 150–250 ms,
  /// and a fixed constant would leave those users with a permanently
  /// out-of-time pulse and no way to fix it.
  int latencyMs = 0;

  void onPosition(Duration position) {
    final current = predicted;
    final driftMs = position.inMilliseconds - current.inMilliseconds;

    if (driftMs.abs() > snapThresholdMs) {
      // A seek or a track change: snapping is correct, and easing across it
      // would drag the pulse through positions the listener never heard.
      _anchorPosition = position;
    } else {
      _anchorPosition = current +
          Duration(
            milliseconds: (driftMs * easeFactor).round(),
          );
    }
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Re-anchors to [position] without easing, and marks the clock stopped.
  void reset(Duration position) {
    _anchorPosition = position;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    _playing = false;
  }

  Duration get predicted {
    if (!_playing) return _anchorPosition;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _anchorWallMs;
    return _anchorPosition + Duration(milliseconds: elapsed);
  }

  /// The position the listener is currently *hearing*, which trails the decoder
  /// by the output latency.
  double get visualPositionMs =>
      predicted.inMilliseconds.toDouble() - latencyMs;
}

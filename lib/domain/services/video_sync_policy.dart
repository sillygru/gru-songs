/// Decides when a muted video surface should be pulled back into line with the
/// audio player, which is the single source of playback truth.
///
/// Pure, like `ShuffleWeightService` — no I/O, no plugin types — so the tuning
/// can be tested directly rather than by staring at a phone.
///
/// The rules exist because a corrective seek is *expensive*: ExoPlayer seeks
/// exactly by default, so every correction decodes forward from the previous
/// keyframe. On a device that is already struggling, correcting on every small
/// drift turns into drift → seek → re-decode → more drift, which reads as
/// constant stutter. So small drift is nudged rarely, and only a genuine
/// discontinuity is corrected on sight.
library;

enum VideoSyncAction {
  /// Leave the video alone.
  none,

  /// Seek the video to the audio position.
  seek,
}

/// Below this the video is considered in sync. Comfortably above the combined
/// staleness of the two clocks: `video_player` refreshes its position from a
/// 100ms platform poll, so a perfectly synced video can still read ~100ms off.
const Duration videoSyncTolerance = Duration(milliseconds: 250);

/// Past this the difference cannot be decoder lag — the user scrubbed, or the
/// audio jumped — so it is corrected immediately, cooldown or not.
const Duration videoSyncJumpThreshold = Duration(milliseconds: 1500);

/// Minimum spacing between corrections for ordinary drift. A device that simply
/// cannot hold sync gets nudged occasionally instead of being seek-spammed into
/// a stall.
const Duration videoSyncCooldown = Duration(seconds: 5);

/// What to do with a video sitting at [videoPosition] while the audio is at
/// [audioPosition].
///
/// [msSinceLastSeek] is the time since the last correction; pass a large value
/// (or [double.infinity]) when there has not been one.
VideoSyncAction resolveVideoSync({
  required Duration audioPosition,
  required Duration videoPosition,
  required bool audioPlaying,
  required bool videoBuffering,
  required bool seekInFlight,
  required double msSinceLastSeek,
}) {
  // Nothing to correct toward while the audio is parked, and seeking on top of
  // a buffering or already-seeking player just queues up more work for a
  // decoder that is visibly behind already.
  if (!audioPlaying || videoBuffering || seekInFlight) {
    return VideoSyncAction.none;
  }

  final drift = (videoPosition - audioPosition).abs();
  if (drift <= videoSyncTolerance) return VideoSyncAction.none;

  if (drift > videoSyncJumpThreshold) return VideoSyncAction.seek;

  return msSinceLastSeek >= videoSyncCooldown.inMilliseconds
      ? VideoSyncAction.seek
      : VideoSyncAction.none;
}

/// The aspect ratio the video actually occupies on screen.
///
/// [VideoPlayerValue.aspectRatio] is not it: the `VideoPlayer` widget wraps its
/// child in a `RotatedBox` for `rotationCorrection`, and on Android's ImageReader
/// backend the reported size is the *unrotated* one. A portrait phone recording
/// therefore arrives as a landscape ratio plus a quarter turn, and laying it out
/// at the raw ratio boxes it wrongly.
double videoDisplayAspectRatio(double rawAspect, int rotationCorrection) {
  if (!rawAspect.isFinite || rawAspect <= 0) return 1.0;

  // Normalised so negative or over-full-turn values behave.
  final quarterTurns = (rotationCorrection ~/ 90) % 4;
  final swapped = quarterTurns == 1 || quarterTurns == 3;
  return swapped ? 1 / rawAspect : rawAspect;
}

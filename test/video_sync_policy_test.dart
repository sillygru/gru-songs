import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/video_sync_policy.dart';

/// Sensible defaults so each test only states the thing it is about.
VideoSyncAction resolve({
  Duration audio = const Duration(seconds: 30),
  Duration video = const Duration(seconds: 30),
  bool audioPlaying = true,
  bool videoBuffering = false,
  bool seekInFlight = false,
  double msSinceLastSeek = double.infinity,
}) {
  return resolveVideoSync(
    audioPosition: audio,
    videoPosition: video,
    audioPlaying: audioPlaying,
    videoBuffering: videoBuffering,
    seekInFlight: seekInFlight,
    msSinceLastSeek: msSinceLastSeek,
  );
}

void main() {
  group('resolveVideoSync', () {
    test('leaves a video in sync alone', () {
      expect(resolve(), VideoSyncAction.none);
    });

    test('tolerates drift within the two clocks\' own staleness', () {
      expect(
        resolve(video: const Duration(seconds: 30, milliseconds: 200)),
        VideoSyncAction.none,
      );
      expect(
        resolve(video: const Duration(seconds: 29, milliseconds: 800)),
        VideoSyncAction.none,
      );
    });

    test('never corrects while the audio is paused', () {
      expect(
        resolve(video: Duration.zero, audioPlaying: false),
        VideoSyncAction.none,
      );
    });

    test('never corrects while the video is buffering', () {
      expect(
        resolve(video: Duration.zero, videoBuffering: true),
        VideoSyncAction.none,
      );
    });

    test('never stacks a seek on top of one already running', () {
      expect(
        resolve(video: Duration.zero, seekInFlight: true),
        VideoSyncAction.none,
      );
    });

    test('holds ordinary drift until the cooldown has passed', () {
      const behind = Duration(seconds: 29, milliseconds: 300);

      expect(
        resolve(video: behind, msSinceLastSeek: 900),
        VideoSyncAction.none,
        reason: 'correcting this often is what made playback stutter',
      );
      expect(
        resolve(video: behind, msSinceLastSeek: 4999),
        VideoSyncAction.none,
      );
      expect(
        resolve(video: behind, msSinceLastSeek: 5000),
        VideoSyncAction.seek,
      );
    });

    test('corrects a real discontinuity immediately, cooldown or not', () {
      // The user scrubbed: no amount of waiting fixes a two-minute gap.
      expect(
        resolve(video: const Duration(minutes: 2), msSinceLastSeek: 0),
        VideoSyncAction.seek,
      );
      expect(
        resolve(video: Duration.zero, msSinceLastSeek: 10),
        VideoSyncAction.seek,
      );
    });

    test('corrects drift in either direction', () {
      expect(
        resolve(video: const Duration(seconds: 40), msSinceLastSeek: 0),
        VideoSyncAction.seek,
      );
      expect(
        resolve(video: const Duration(seconds: 20), msSinceLastSeek: 0),
        VideoSyncAction.seek,
      );
    });

    test('a discontinuity still yields to buffering and in-flight seeks', () {
      expect(
        resolve(video: Duration.zero, videoBuffering: true),
        VideoSyncAction.none,
      );
      expect(
        resolve(video: Duration.zero, seekInFlight: true),
        VideoSyncAction.none,
      );
    });
  });

  group('videoDisplayAspectRatio', () {
    test('passes an upright video through unchanged', () {
      expect(videoDisplayAspectRatio(16 / 9, 0), closeTo(16 / 9, 1e-9));
      expect(videoDisplayAspectRatio(16 / 9, 180), closeTo(16 / 9, 1e-9));
    });

    test('inverts a quarter-turned video', () {
      // A portrait phone recording: reported landscape, rendered upright by the
      // RotatedBox the VideoPlayer widget wraps around it.
      expect(videoDisplayAspectRatio(16 / 9, 90), closeTo(9 / 16, 1e-9));
      expect(videoDisplayAspectRatio(16 / 9, 270), closeTo(9 / 16, 1e-9));
    });

    test('normalises rotations outside a single turn', () {
      expect(videoDisplayAspectRatio(16 / 9, 360), closeTo(16 / 9, 1e-9));
      expect(videoDisplayAspectRatio(16 / 9, 450), closeTo(9 / 16, 1e-9));
      expect(videoDisplayAspectRatio(16 / 9, -90), closeTo(9 / 16, 1e-9));
    });

    test('falls back to square on a degenerate ratio', () {
      // What VideoPlayerValue reports before it is initialized, or for a file
      // whose dimensions never arrive.
      expect(videoDisplayAspectRatio(0, 0), 1.0);
      expect(videoDisplayAspectRatio(-2, 0), 1.0);
      expect(videoDisplayAspectRatio(double.nan, 90), 1.0);
      expect(videoDisplayAspectRatio(double.infinity, 0), 1.0);
    });
  });
}

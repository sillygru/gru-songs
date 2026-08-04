import 'dart:async';

/// How urgently a gated decode needs the CPU. A running decode is never
/// preempted — FFmpeg sessions cannot be cheaply interrupted — so priority only
/// reorders the *waiting* queue.
enum MediaDecodePriority {
  /// User-facing work: the seek bar's waveform extraction. Jumps ahead of any
  /// queued normal work so the bar appears as soon as the file can be decoded.
  high,

  /// Background / speculative work: beat analysis (current and next-track
  /// prefetch) and the FFmpeg cover-extraction fallback.
  normal,
}

/// Serializes the app's expensive full-file decodes across services.
///
/// Waveform extraction and beat analysis each used to queue internally but run
/// beside each other, so the first play of an uncached track could have two
/// FFmpeg sessions decoding the same file while just_audio was still buffering
/// it — three readers thrashing one file and starving the audio thread. Every
/// decode that runs through this gate executes one at a time, so the second
/// one starts only when the first has written its output and freed the CPU.
///
/// High-priority starvation of normal work is bounded in practice: waveform
/// requests arrive at most once per uncached song and stop entirely after the
/// first play-through, and beat analysis caps itself at two queued prefetches.
class MediaDecodeGate {
  MediaDecodeGate._();

  static final List<_DecodeJob> _waiting = [];
  static bool _running = false;

  /// Runs [body] once every previously queued decode has finished.
  ///
  /// [priority] reorders the queue, not the running job: [high] work (the
  /// waveform the user is looking at) is served before [normal] work (a beat
  /// prefetch nobody is waiting on yet). Within one priority the queue stays
  /// FIFO.
  ///
  /// Errors from [body] propagate to the caller, but never poison the gate — a
  /// failed decode must not silently drop everything queued behind it.
  static Future<T> run<T>(
    Future<T> Function() body, {
    MediaDecodePriority priority = MediaDecodePriority.normal,
  }) {
    final job = _DecodeJob<T>(body, priority: priority);
    if (priority == MediaDecodePriority.high) {
      // Land ahead of every queued normal job, but behind earlier high ones.
      final firstNormal = _waiting.indexWhere(
        (queued) => queued.priority != MediaDecodePriority.high,
      );
      _waiting.insert(firstNormal == -1 ? _waiting.length : firstNormal, job);
    } else {
      _waiting.add(job);
    }
    _drain();
    return job.result.future;
  }

  static void _drain() {
    if (_running || _waiting.isEmpty) return;
    _running = true;
    final job = _waiting.removeAt(0);
    unawaited(() async {
      try {
        job.result.complete(await job.body());
      } catch (e, st) {
        job.result.completeError(e, st);
      } finally {
        _running = false;
        _drain();
      }
    }());
  }
}

class _DecodeJob<T> {
  final Future<T> Function() body;
  final MediaDecodePriority priority;
  final Completer<T> result = Completer<T>();

  _DecodeJob(this.body, {required this.priority});
}

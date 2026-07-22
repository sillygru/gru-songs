import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/services/cover_warm_order.dart';
import '../models/song.dart';
import 'cover_refresh_service.dart';
import 'file_manager_service.dart';

/// Produces the square notification covers for a playback queue passively, one
/// song at a time, instead of all at once when the queue is built.
///
/// Building them eagerly meant a cold start spawned an image-decode isolate per
/// song before anything could play. Now only the song the user actually starts
/// is processed on the spot; everything else trickles through here in the order
/// it is likely to be needed, and a song whose cover is not ready yet simply
/// shows its raw (uncropped) art in the notification for that session.
class NotificationCoverWarmer {
  static final NotificationCoverWarmer instance =
      NotificationCoverWarmer._internal();

  NotificationCoverWarmer._internal();

  /// Decode + crop + encode is expensive on a budget device, and this work is
  /// never urgent — one at a time, with a breather in between, keeps it off the
  /// UI thread's back.
  static const Duration _breather = Duration(milliseconds: 250);

  /// How long to idle before re-checking a back-off condition (a running scan,
  /// or the app being in the background).
  static const Duration _retryDelay = Duration(seconds: 2);

  /// How many songs we are still willing to process while backgrounded — just
  /// enough that an auto-advance or two lands on correct art.
  static const int _backgroundBudget = 2;

  final FileManagerService _fileManager = FileManagerService();

  List<Song> _pending = const [];
  final Set<String> _done = {};
  bool _foreground = true;
  int _pauseDepth = 0;
  bool _running = false;
  int _backgroundProcessed = 0;
  PlayerCoverSizingMode _mode = PlayerCoverSizingMode.autoFit;

  /// Replaces the work list with [queue] reprioritised around [currentIndex],
  /// so whatever plays next is always at the front.
  void setQueue(
    List<Song> queue,
    int currentIndex,
    PlayerCoverSizingMode mode,
  ) {
    _mode = mode;
    if (mode != PlayerCoverSizingMode.autoFit || queue.isEmpty) {
      _pending = const [];
      return;
    }

    final seen = <String>{};
    _pending = orderForWarming(queue, currentIndex)
        .where((song) => song.coverUrl != null && song.coverUrl!.isNotEmpty)
        .where((song) => !_done.contains(song.filename))
        .where((song) => seen.add(song.filename))
        .toList();
    _schedule();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) _backgroundProcessed = 0;
    _schedule();
  }

  /// Holds warming off while a library scan runs. Scanning already saturates
  /// the device with isolate work, and this can always wait. Nests, so
  /// overlapping scan passes each hold their own claim.
  void pushPause() => _pauseDepth++;

  void popPause() {
    if (_pauseDepth > 0) _pauseDepth--;
    _schedule();
  }

  @visibleForTesting
  int get pendingCount => _pending.length;

  @visibleForTesting
  void resetForTest() {
    _pending = const [];
    _done.clear();
    _foreground = true;
    _pauseDepth = 0;
    _backgroundProcessed = 0;
  }

  void _schedule() {
    if (_running || _pending.isEmpty) return;
    _running = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        await _waitForWorkableMoment();
        if (_pending.isEmpty) return;

        // Re-read the head each pass: setQueue may have reprioritised it while
        // the previous song was being processed.
        final song = _pending.first;
        _pending = _pending.sublist(1);
        if (_done.contains(song.filename)) continue;

        if (FileManagerService.peekNotificationCover(song, _mode) != null) {
          _done.add(song.filename);
          continue;
        }

        if (!_foreground) _backgroundProcessed++;

        try {
          await _fileManager.getOrCreateNotificationCover(song, _mode);
        } catch (e) {
          debugPrint('NotificationCoverWarmer: ${song.filename} failed: $e');
        }
        // Either it worked, or it will not work for this file; either way don't
        // come back to it this session.
        _done.add(song.filename);

        await Future<void>.delayed(_breather);
      }
    } finally {
      _running = false;
    }
  }

  /// Idles until warming is appropriate again.
  Future<void> _waitForWorkableMoment() async {
    while (_pending.isNotEmpty && !_canWorkNow) {
      await Future<void>.delayed(_retryDelay);
    }
  }

  bool get _canWorkNow {
    if (_pauseDepth > 0) return false;
    // Covers the user is looking at right now come first.
    if (CoverRefreshService.instance.isBusy) return false;
    if (!_foreground && _backgroundProcessed >= _backgroundBudget) return false;
    return true;
  }
}

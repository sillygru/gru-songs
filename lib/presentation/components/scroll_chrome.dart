import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

/// Drives the chrome that reacts to scrolling — the bottom nav dock and the
/// header scrim — from one place.
///
/// Home, Library and Profile each carried a byte-identical copy of this
/// handler. Mix it in instead, hand every vertical scroll view's
/// [NotificationListener] its [handleScrollNotification], and read [isScrolled]
/// for the header.
mixin ScrollChromeMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _isScrolled = false;

  /// Whether the content has scrolled off the top — drives the header scrim.
  bool get isScrolled => _isScrolled;

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final scrolled = notification.metrics.pixels > 0;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }

    final dock = ref.read(bottomDockVisibilityProvider.notifier);

    // Back at the top there is nothing to make room for, so the dock always
    // comes back — no drag needed.
    if (notification.metrics.pixels <= 0) {
      dock.show();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;

      // Momentum carrying the list upward counts as reaching for the dock, so
      // an unattended fling reveals too. Only upward, though: a downward fling
      // shouldn't sweep the bar away after the finger has already left.
      if (notification.dragDetails != null || delta < 0) {
        dock.updateFromDrag(scrollDelta: delta);
      }
    } else if (notification is ScrollEndNotification) {
      dock.settle();
    }
    return false;
  }
}

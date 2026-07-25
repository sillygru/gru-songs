import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/spectrum_bars.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import 'spectrum_controller.dart';

/// Four bars over the album art of whatever is playing.
///
/// Low frequencies on the left, high on the right. In
/// [VisualizerMode.synced] the heights come from the track's own band
/// envelopes at the playhead — see [SpectrumController]; in
/// [VisualizerMode.classic] they walk toward random targets, which is what this
/// widget did for its whole life before the beat map existed.
///
/// The widget owns no animation. It subscribes to the shared controller and
/// paints; a frame repaints four rounded rectangles and never rebuilds a
/// widget or runs layout. That matters because this thing is on screen in the
/// now-playing bar on every screen in the app.
class AudioVisualizer extends ConsumerStatefulWidget {
  final Color color;
  final double width;
  final double height;
  final bool isPlaying;
  final VisualizerMode mode;

  const AudioVisualizer({
    super.key,
    this.color = Colors.white,
    this.width = 24,
    this.height = 24,
    this.isPlaying = true,
    this.mode = VisualizerMode.synced,
  });

  @override
  ConsumerState<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends ConsumerState<AudioVisualizer> {
  SpectrumController? _controller;
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= ref.read(spectrumControllerProvider);
    // TickerMode is false whenever this subtree is parked behind another route
    // — the player screen open over the library, say. Dropping the subscription
    // there is what lets the shared controller stop its ticker entirely once
    // nothing visible is watching.
    _setSubscribed(TickerMode.valuesOf(context).enabled && _wantsMotion);
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying ||
        widget.mode != oldWidget.mode) {
      _setSubscribed(TickerMode.valuesOf(context).enabled && _wantsMotion);
    }
  }

  bool get _wantsMotion =>
      widget.isPlaying && widget.mode != VisualizerMode.off;

  void _setSubscribed(bool value) {
    if (_subscribed == value) return;
    _subscribed = value;
    final controller = _controller;
    if (controller == null) return;
    if (value) {
      controller.addListener(_onFrame);
    } else {
      controller.removeListener(_onFrame);
    }
  }

  // The painter repaints off the controller directly, so a frame does not need
  // to come through here at all. The subscription exists to tell the controller
  // that something is watching.
  void _onFrame() {}

  @override
  void dispose() {
    _setSubscribed(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _BarsPainter(
          controller: controller,
          color: widget.color,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final SpectrumController controller;
  final Color color;

  _BarsPainter({
    required this.controller,
    required this.color,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (SpectrumBars.barCount * 2);
    // spaceEvenly, matching the Row this replaced: equal gaps at the ends and
    // between the bars.
    final gap = (size.width - barWidth * SpectrumBars.barCount) /
        (SpectrumBars.barCount + 1);
    final radius = Radius.circular(barWidth / 2);
    final paint = Paint()..color = color;

    for (var i = 0; i < SpectrumBars.barCount; i++) {
      final barHeight = size.height * controller.levels[i];
      final left = gap + i * (barWidth + gap);
      final top = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) => oldDelegate.color != color;
}

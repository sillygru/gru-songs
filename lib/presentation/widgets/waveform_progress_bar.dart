import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

class WaveformProgressBar extends ConsumerStatefulWidget {
  final String filename;
  final String path;
  final Duration progress;
  final Duration total;
  final Function(Duration) onSeek;

  const WaveformProgressBar({
    super.key,
    required this.filename,
    required this.path,
    required this.progress,
    required this.total,
    required this.onSeek,
  });

  @override
  ConsumerState<WaveformProgressBar> createState() =>
      _WaveformProgressBarState();
}

class _WaveformProgressBarState extends ConsumerState<WaveformProgressBar> {
  List<double>? _peaks;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(WaveformProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    if (widget.filename.isEmpty || widget.path.isEmpty) return;

    setState(() {
      _isLoading = true;
      _peaks = null;
    });

    try {
      final waveformService = ref.read(waveformServiceProvider);
      final currentFilename = widget.filename;
      final peaks =
          await waveformService.getWaveform(widget.filename, widget.path);

      if (mounted && widget.filename == currentFilename) {
        setState(() {
          _peaks = peaks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "${duration.inMinutes}:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx;
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            widget.onSeek(widget.total * percent);
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx;
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            widget.onSeek(widget.total * percent);
          },
          child: SizedBox(
            height: 60,
            width: double.infinity,
            child: _isLoading
                ? Center(
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : (_peaks == null || _peaks!.isEmpty)
                    ? Container(
                        height: 2,
                        color: Colors.white.withValues(alpha: 0.1),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: widget.total.inMilliseconds > 0
                              ? (widget.progress.inMilliseconds /
                                      widget.total.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0.0,
                          child: Container(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      )
                    : CustomPaint(
                        painter: WaveformPainter(
                          peaks: _peaks!,
                          progress: widget.total.inMilliseconds > 0
                              ? (widget.progress.inMilliseconds /
                                      widget.total.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0.0,
                          activeColor: Theme.of(context).colorScheme.primary,
                          inactiveColor: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(widget.progress),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              _formatDuration(widget.total),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const barWidth = 2.0;
    const spacing = 1.0;
    final step = barWidth + spacing;
    final totalBars = (size.width / step).floor();

    if (totalBars <= 0) return;

    final displayPeaks = _downsample(peaks, totalBars);

    final yCenter = size.height / 2;
    final activeBars = (progress * displayPeaks.length).floor();

    for (int i = 0; i < displayPeaks.length; i++) {
      double v = displayPeaks[i];

      final shapedV = _calibrateAmplitude(v);
      final barHeight = math.max(1.0, shapedV * size.height * 0.85);

      final x = i * step + barWidth / 2;
      paint.color = i < activeBars ? activeColor : inactiveColor;
      paint.strokeWidth = barWidth;

      canvas.drawLine(
        Offset(x, yCenter - barHeight / 2),
        Offset(x, yCenter + barHeight / 2),
        paint,
      );
    }
  }

  double _calibrateAmplitude(double amplitude) {
    if (amplitude < 0.15) return amplitude * 0.8;
    if (amplitude < 0.35) return 0.12 + (amplitude - 0.15) * 0.6;
    if (amplitude < 0.6) return 0.24 + (amplitude - 0.35) * 0.5;
    if (amplitude < 0.8) return 0.36 + (amplitude - 0.6) * 0.5;
    return 0.46 + (amplitude - 0.8) * 0.4;
  }

  List<double> _downsample(List<double> samples, int targetCount) {
    if (samples.length == targetCount) return samples;

    final List<double> result = [];
    final stepSize = samples.length / targetCount;
    for (int i = 0; i < targetCount; i++) {
      int start = (i * stepSize).floor();
      int end = ((i + 1) * stepSize).floor();
      if (end > samples.length) end = samples.length;

      if (start >= end) {
        result.add(samples[start.clamp(0, samples.length - 1)]);
        continue;
      }

      double max = 0;
      for (int j = start; j < end; j++) {
        if (samples[j] > max) max = samples[j];
      }
      result.add(max);
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.peaks != peaks ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

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
                              .withAlpha((0.5 * 255).round()),
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
                      : () {
                          final box = context.findRenderObject() as RenderBox;
                          final totalBars = (box.size.width / 3).floor();
                          final displayPeaks = _downsample(_peaks!, totalBars);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            mainAxisSize: MainAxisSize.max,
                            children: displayPeaks.asMap().entries.map((entry) {
                              final i = entry.key;
                              final v = entry.value;
                              final isActive = i <
                                  (widget.total.inMilliseconds > 0
                                          ? (widget.progress.inMilliseconds /
                                                      widget
                                                          .total.inMilliseconds)
                                                  .clamp(0.0, 1.0) *
                                              displayPeaks.length
                                          : 0.0)
                                      .floor();
                              final size = box.size;
                              return SizedBox(
                                height: (v * size.height * 25).clamp(3.0, size.height * 0.85),
                                width: 2.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(1.0),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        }()),
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
}

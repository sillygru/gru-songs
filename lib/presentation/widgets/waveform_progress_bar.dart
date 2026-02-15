import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

final Set<String> _sessionViewedSongs = {};

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

class _WaveformProgressBarState extends ConsumerState<WaveformProgressBar>
    with TickerProviderStateMixin {
  List<double>? _peaks;
  bool _isLoading = false;
  late AnimationController _barAnimationController;
  late Animation<double> _barAnimation;
  bool _isDragging = false;
  double? _dragPosition;
  late bool _hasViewed; // Remove 'final' keyword

  @override
  void initState() {
    super.initState();
    // Check BEFORE the async call to avoid race conditions
    _hasViewed = _sessionViewedSongs.contains(widget.filename);
    _barAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: _hasViewed ? 1.0 : 0.0,
    );
    _barAnimation = CurvedAnimation(
      parent: _barAnimationController,
      curve: Curves.easeOutCubic,
    );
    _loadWaveform();
  }

  @override
  void dispose() {
    _barAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WaveformProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      // Update _hasViewed for the new song
      _hasViewed = _sessionViewedSongs.contains(widget.filename);

      if (_hasViewed) {
        // Already viewed - set to final state immediately
        _barAnimationController.value = 1.0;
      } else {
        // Not viewed yet - reset to start animation
        _barAnimationController.reset();
      }

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
          // Mark as viewed immediately when data loads, but don't animate
          _sessionViewedSongs.add(widget.filename);
        });
        // Only animate on first view
        if (!_hasViewed) {
          _barAnimationController.forward();
        }
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

  double _getCurrentProgress() {
    if (_isDragging && _dragPosition != null) {
      return _dragPosition!;
    }
    return widget.total.inMilliseconds > 0
        ? (widget.progress.inMilliseconds / widget.total.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              final box = context.findRenderObject() as RenderBox;
              final x = details.localPosition.dx;
              _dragPosition = (x / box.size.width).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              final box = context.findRenderObject() as RenderBox;
              final x = details.localPosition.dx;
              _dragPosition = (x / box.size.width).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            if (_dragPosition != null) {
              widget.onSeek(widget.total * _dragPosition!);
            }
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
          },
          onTapUp: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
            widget.onSeek(widget.total * percent);
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            setState(() {
              _isDragging = true;
              _dragPosition = percent;
            });
          },
          child: Container(
            height: 60,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_isLoading) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: WaveformPainter(
                      peaks: null,
                      progress: _getCurrentProgress(),
                      color: Theme.of(context).colorScheme.primary,
                      animationValue: 1.0,
                      isLoading: true,
                    ),
                  );
                }

                if (_peaks == null || _peaks!.isEmpty) {
                  return Container(
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.1),
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      width: constraints.maxWidth * _getCurrentProgress(),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                }

                return AnimatedBuilder(
                  animation: _barAnimation,
                  builder: (context, child) {
                    final totalBars = (constraints.maxWidth / 3).floor();
                    final displayPeaks = _downsample(_peaks!, totalBars);

                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: WaveformPainter(
                        peaks: displayPeaks,
                        progress: _getCurrentProgress(),
                        color: Theme.of(context).colorScheme.primary,
                        animationValue: _barAnimation.value,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(_isDragging && _dragPosition != null
                  ? widget.total * _dragPosition!
                  : widget.progress),
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

class WaveformPainter extends CustomPainter {
  final List<double>? peaks;
  final double progress;
  final Color color;
  final double animationValue;
  final bool isLoading;

  WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.color,
    required this.animationValue,
    this.isLoading = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 2.0;
    final spacing = 1.0;
    final totalBars = (size.width / (barWidth + spacing)).floor();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    if (isLoading) {
      final progressBarIndex = progress * totalBars;
      for (int i = 0; i < totalBars; i++) {
        final distanceFromProgress = (i - progressBarIndex).abs();
        final isActive = i < progressBarIndex;

        double colorIntensity = 1.0;
        if (distanceFromProgress < 2) {
          colorIntensity = isActive ? 1.0 : (2 - distanceFromProgress) / 2;
        } else {
          colorIntensity = isActive ? 1.0 : 0.0;
        }

        paint.color = Color.lerp(
          Colors.white.withValues(alpha: 0.15),
          color,
          colorIntensity,
        )!;

        final x = i * (barWidth + spacing) + spacing / 2;
        final barHeight = size.height * 0.05;
        final y = (size.height - barHeight) / 2;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barWidth, barHeight),
            const Radius.circular(1.0),
          ),
          paint,
        );
      }
      return;
    }

    if (peaks == null || peaks!.isEmpty) return;

    final actualPeaks = peaks!;
    // Compensate for audio buffer latency (~150ms typical on mobile)
    // by shifting progress backward so waveform aligns with actual audio output
    final barOffset = 2.35 / actualPeaks.length;
    final adjustedProgress = (progress - barOffset).clamp(0.0, 1.0);
    final progressBarIndex = adjustedProgress * actualPeaks.length;

    for (int i = 0; i < actualPeaks.length; i++) {
      final v = actualPeaks[i];
      final distanceFromProgress = (i - progressBarIndex).abs();
      final isActive = i < progressBarIndex;

      double colorIntensity = 1.0;
      if (distanceFromProgress < 2) {
        colorIntensity = isActive ? 1.0 : (2 - distanceFromProgress) / 2;
      } else {
        colorIntensity = isActive ? 1.0 : 0.0;
      }

      paint.color = Color.lerp(
        Colors.white.withValues(alpha: 0.1),
        color,
        colorIntensity,
      )!;

      final targetHeight = (v * size.height * 35).clamp(3.0, size.height * 0.9);
      final animatedHeight = targetHeight * animationValue;

      final x = i * (barWidth + spacing) + spacing / 2;
      final y = (size.height - animatedHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, animatedHeight),
          const Radius.circular(1.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isLoading != isLoading;
  }
}

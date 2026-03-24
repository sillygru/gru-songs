import 'dart:async';
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
  final Stream<Duration>? positionStream;

  const WaveformProgressBar({
    super.key,
    required this.filename,
    required this.path,
    required this.progress,
    required this.total,
    required this.onSeek,
    this.positionStream,
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
  double? _dragPosition;
  late bool _hasViewed;
  StreamSubscription<Duration>? _positionSubscription;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<double?> _dragPositionNotifier = ValueNotifier(null);
  
  List<double>? _cachedDisplayPeaks;
  double _cachedWidth = 0;
  TextStyle? _labelStyle;
  String _formattedTotalTime = '0:00';

  @override
  void initState() {
    super.initState();
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
    _subscribeToPositionStream();
  }

  @override
  void dispose() {
    _barAnimationController.dispose();
    _positionSubscription?.cancel();
    _positionNotifier.dispose();
    _dragPositionNotifier.dispose();
    super.dispose();
  }

  void _subscribeToPositionStream() {
    _positionSubscription?.cancel();
    if (widget.positionStream == null) return;

    _positionSubscription = widget.positionStream!.listen((position) {
      if (_positionNotifier.value.inSeconds != position.inSeconds) {
        _positionNotifier.value = position;
      } else {
        // Still update for smoother sub-second progress if needed by painter
        _positionNotifier.value = position;
      }
    });
  }

  @override
  void didUpdateWidget(WaveformProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      _hasViewed = _sessionViewedSongs.contains(widget.filename);
      _positionNotifier.value = Duration.zero;
      _cachedDisplayPeaks = null;
      _cachedWidth = 0;
      _labelStyle = null;

      if (_hasViewed) {
        _barAnimationController.value = 1.0;
      } else {
        _barAnimationController.reset();
      }

      _loadWaveform();
    }

    if (oldWidget.total != widget.total) {
      _formattedTotalTime = _formatDuration(widget.total);
    }

    if (oldWidget.positionStream != widget.positionStream) {
      _subscribeToPositionStream();
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
          _sessionViewedSongs.add(widget.filename);
        });
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

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    _labelStyle ??= TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );
    if (_formattedTotalTime.isEmpty || _formattedTotalTime == '0:00') {
      _formattedTotalTime = _formatDuration(widget.total);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx;
            _dragPosition = (x / box.size.width).clamp(0.0, 1.0);
            _dragPositionNotifier.value = _dragPosition;
          },
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx;
            _dragPosition = (x / box.size.width).clamp(0.0, 1.0);
            _dragPositionNotifier.value = _dragPosition;
          },
          onHorizontalDragEnd: (details) {
            if (_dragPosition != null) {
              widget.onSeek(widget.total * _dragPosition!);
            }
            _dragPosition = null;
            _dragPositionNotifier.value = null;
          },
          onTapUp: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            _dragPosition = null;
            _dragPositionNotifier.value = null;
            widget.onSeek(widget.total * percent);
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            _dragPosition = percent;
            _dragPositionNotifier.value = percent;
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
                      positionNotifier: _positionNotifier,
                      dragPositionNotifier: _dragPositionNotifier,
                      total: widget.total,
                      color: primaryColor,
                      animationValue: 1.0,
                      isLoading: true,
                    ),
                  );
                }

                if (_peaks == null || _peaks!.isEmpty) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: _positionNotifier,
                    builder: (context, position, child) {
                      final progress = widget.total.inMilliseconds > 0
                          ? (position.inMilliseconds /
                                  widget.total.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0;
                      return Container(
                        height: 2,
                        color: Colors.white.withValues(alpha: 0.1),
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOut,
                          width: constraints.maxWidth * progress,
                          color: primaryColor,
                        ),
                      );
                    },
                  );
                }

                final width = constraints.maxWidth;
                if (_cachedWidth != width || _cachedDisplayPeaks == null) {
                  _cachedWidth = width;
                  final totalBars = (width / 3).floor();
                  _cachedDisplayPeaks = _downsample(_peaks!, totalBars);
                }

                return AnimatedBuilder(
                  animation: _barAnimation,
                  builder: (context, child) {
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: WaveformPainter(
                        peaks: _cachedDisplayPeaks,
                        positionNotifier: _positionNotifier,
                        dragPositionNotifier: _dragPositionNotifier,
                        total: widget.total,
                        color: primaryColor,
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
            ValueListenableBuilder<double?>(
              valueListenable: _dragPositionNotifier,
              builder: (context, dragPos, child) {
                if (dragPos != null) {
                  return Text(
                    _formatDuration(widget.total * dragPos),
                    style: _labelStyle,
                  );
                }
                return ValueListenableBuilder<Duration>(
                  valueListenable: _positionNotifier,
                  builder: (context, position, child) {
                    return Text(
                      _formatDuration(position),
                      style: _labelStyle,
                    );
                  },
                );
              },
            ),
            Text(
              _formattedTotalTime,
              style: _labelStyle,
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
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<double?> dragPositionNotifier;
  final Duration total;
  final Color color;
  final double animationValue;
  final bool isLoading;

  WaveformPainter({
    required this.peaks,
    required this.positionNotifier,
    required this.dragPositionNotifier,
    required this.total,
    required this.color,
    required this.animationValue,
    this.isLoading = false,
  }) : super(repaint: Listenable.merge([positionNotifier, dragPositionNotifier]));

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 2.0;
    final spacing = 1.0;
    final totalBarsCount = (size.width / (barWidth + spacing)).floor();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    double progress;
    if (dragPositionNotifier.value != null) {
      progress = dragPositionNotifier.value!;
    } else {
      progress = total.inMilliseconds > 0
          ? (positionNotifier.value.inMilliseconds / total.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;
    }

    if (isLoading) {
      final progressBarIndex = progress * totalBarsCount;
      for (int i = 0; i < totalBarsCount; i++) {
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
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isLoading != isLoading ||
        oldDelegate.total != total;
  }
}

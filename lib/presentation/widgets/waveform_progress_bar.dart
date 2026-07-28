import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

/// Thin placeholder height while an uncached waveform is still generating.
const double _collapsedAmplitude = 0.28;

/// Let playback settle before kicking off an uncached FFmpeg decode.
const Duration _uncachedExtractDelay = Duration(milliseconds: 2800);

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
    with SingleTickerProviderStateMixin {
  List<double>? _peaks;
  late AnimationController _barAnimationController;
  late Animation<double> _barAnimation;
  double? _dragPosition;
  StreamSubscription<Duration>? _positionSubscription;
  DateTime? _lastPositionUpdate;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<double?> _dragPositionNotifier = ValueNotifier(null);

  List<double>? _cachedDisplayPeaks;
  double _cachedWidth = 0;
  TextStyle? _labelStyle;
  String _formattedTotalTime = '0:00';

  AnimationStatusListener? _routeStatusListener;
  Animation<double>? _monitoredAnimation;
  Timer? _deferTimer;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _barAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 0.0,
    );
    _barAnimation = CurvedAnimation(
      parent: _barAnimationController,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleWaveformLoad();
    });
    _subscribeToPositionStream();
  }

  @override
  void dispose() {
    _cleanupRouteListener();
    _deferTimer?.cancel();
    _loadToken++;
    _barAnimationController.dispose();
    _positionSubscription?.cancel();
    _positionNotifier.dispose();
    _dragPositionNotifier.dispose();
    super.dispose();
  }

  void _cleanupRouteListener() {
    if (_routeStatusListener != null && _monitoredAnimation != null) {
      _monitoredAnimation!.removeStatusListener(_routeStatusListener!);
      _routeStatusListener = null;
      _monitoredAnimation = null;
    }
  }

  void _subscribeToPositionStream() {
    _positionSubscription?.cancel();
    if (widget.positionStream == null) return;

    _positionSubscription = widget.positionStream!.listen((position) {
      final now = DateTime.now();
      if (_lastPositionUpdate == null ||
          now.difference(_lastPositionUpdate!).inMilliseconds > 200) {
        _lastPositionUpdate = now;
        _positionNotifier.value = position;
      }
    });
  }

  @override
  void didUpdateWidget(WaveformProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      _loadToken++;
      _deferTimer?.cancel();
      _cleanupRouteListener();
      _positionNotifier.value = Duration.zero;
      _cachedDisplayPeaks = null;
      _cachedWidth = 0;
      _labelStyle = null;
      _peaks = null;
      _barAnimationController.value = 0.0;

      _scheduleWaveformLoad();
    }

    if (oldWidget.total != widget.total) {
      _formattedTotalTime = _formatDuration(widget.total);
    }

    if (oldWidget.positionStream != widget.positionStream) {
      _subscribeToPositionStream();
    }
  }

  Future<void> _scheduleWaveformLoad() async {
    _cleanupRouteListener();
    _deferTimer?.cancel();
    if (widget.filename.isEmpty || widget.path.isEmpty) return;

    final currentFilename = widget.filename;
    final token = ++_loadToken;
    final waveformService = ref.read(waveformServiceProvider);

    final isCached = await waveformService.isWaveformCached(currentFilename);
    if (!mounted || widget.filename != currentFilename || token != _loadToken) {
      return;
    }

    if (isCached) {
      // Already on disk — show the full waveform immediately.
      await _loadWaveform(expandFromCollapsed: false);
      return;
    }

    // Uncached: wait out the route transition, then give playback a few
    // seconds before FFmpeg wakes up so the audio thread is not starved.
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation != null && !animation.isCompleted) {
      _monitoredAnimation = animation;
      _routeStatusListener = (status) {
        if (status == AnimationStatus.completed) {
          _cleanupRouteListener();
          if (mounted &&
              widget.filename == currentFilename &&
              token == _loadToken) {
            _deferUncachedExtract(currentFilename, token);
          }
        }
      };
      animation.addStatusListener(_routeStatusListener!);
      return;
    }

    _deferUncachedExtract(currentFilename, token);
  }

  void _deferUncachedExtract(String filename, int token) {
    _deferTimer?.cancel();
    _deferTimer = Timer(_uncachedExtractDelay, () {
      if (!mounted || widget.filename != filename || token != _loadToken) {
        return;
      }
      // Idle priority: yield to animations / gestures that landed in the delay.
      unawaited(
        SchedulerBinding.instance.scheduleTask(
          () {
            if (!mounted ||
                widget.filename != filename ||
                token != _loadToken) {
              return;
            }
            unawaited(_loadWaveform(expandFromCollapsed: true));
          },
          Priority.idle,
          debugLabel: 'waveformExtract',
        ),
      );
    });
  }

  Future<void> _loadWaveform({required bool expandFromCollapsed}) async {
    if (widget.filename.isEmpty || widget.path.isEmpty) return;

    final token = _loadToken;
    final currentFilename = widget.filename;

    try {
      final waveformService = ref.read(waveformServiceProvider);
      final peaks =
          await waveformService.getWaveform(widget.filename, widget.path);

      if (!mounted ||
          widget.filename != currentFilename ||
          token != _loadToken) {
        return;
      }

      setState(() {
        _peaks = peaks;
        _cachedDisplayPeaks = null;
        _cachedWidth = 0;
      });

      if (peaks.isEmpty) return;

      if (expandFromCollapsed) {
        _barAnimationController.value = _collapsedAmplitude;
        unawaited(_barAnimationController.forward());
      } else {
        _barAnimationController.value = 1.0;
      }
    } catch (e) {
      debugPrint('WaveformProgressBar: load failed: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '${duration.inMinutes}:$twoDigitSeconds';
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
                final peaks = _peaks;
                if (peaks == null || peaks.isEmpty) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: _positionNotifier,
                    builder: (context, position, child) {
                      final progress = widget.total.inMilliseconds > 0
                          ? (position.inMilliseconds /
                                  widget.total.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0;
                      return CustomPaint(
                        size: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        painter: WaveformPainter(
                          peaks: null,
                          positionNotifier: _positionNotifier,
                          dragPositionNotifier: _dragPositionNotifier,
                          total: widget.total,
                          color: primaryColor,
                          animationValue: _collapsedAmplitude,
                          isCollapsedPlaceholder: true,
                          progressOverride: progress,
                        ),
                      );
                    },
                  );
                }

                final width = constraints.maxWidth;
                if (_cachedWidth != width || _cachedDisplayPeaks == null) {
                  _cachedWidth = width;
                  final totalBars = (width / 3).floor();
                  _cachedDisplayPeaks = _downsample(peaks, totalBars);
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

    final result = <double>[];
    final stepSize = samples.length / targetCount;
    for (var i = 0; i < targetCount; i++) {
      var start = (i * stepSize).floor();
      var end = ((i + 1) * stepSize).floor();
      if (end > samples.length) end = samples.length;

      if (start >= end) {
        result.add(samples[start.clamp(0, samples.length - 1)]);
        continue;
      }

      var max = 0.0;
      for (var j = start; j < end; j++) {
        if (samples[j] > max) max = samples[j];
      }
      result.add(max);
    }
    return result;
  }
}

@visibleForTesting
double calculateWaveformBarHeight(double amplitude, double height) {
  final shapedAmplitude = calibrateWaveformAmplitude(amplitude);
  return math.max(1.0, shapedAmplitude * height * 0.85);
}

@visibleForTesting
double calibrateWaveformAmplitude(double amplitude) {
  if (amplitude < 0.15) return amplitude * 0.8;
  if (amplitude < 0.35) return 0.12 + (amplitude - 0.15) * 0.6;
  if (amplitude < 0.6) return 0.24 + (amplitude - 0.35) * 0.5;
  if (amplitude < 0.8) return 0.36 + (amplitude - 0.6) * 0.5;
  return 0.46 + (amplitude - 0.8) * 0.4;
}

class WaveformPainter extends CustomPainter {
  final List<double>? peaks;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<double?> dragPositionNotifier;
  final Duration total;
  final Color color;
  final double animationValue;
  final bool isCollapsedPlaceholder;
  final double? progressOverride;

  WaveformPainter({
    required this.peaks,
    required this.positionNotifier,
    required this.dragPositionNotifier,
    required this.total,
    required this.color,
    required this.animationValue,
    this.isCollapsedPlaceholder = false,
    this.progressOverride,
  }) : super(
          repaint: Listenable.merge([positionNotifier, dragPositionNotifier]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const spacing = 1.0;
    final totalBarsCount = (size.width / (barWidth + spacing)).floor();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double progress;
    if (dragPositionNotifier.value != null) {
      progress = dragPositionNotifier.value!;
    } else if (progressOverride != null) {
      progress = progressOverride!;
    } else {
      progress = total.inMilliseconds > 0
          ? (positionNotifier.value.inMilliseconds / total.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;
    }

    final peakData = peaks;
    if (isCollapsedPlaceholder || peakData == null || peakData.isEmpty) {
      final progressBarIndex = progress * totalBarsCount;
      final heightScale =
          (animationValue / _collapsedAmplitude).clamp(0.35, 1.0);
      final barHeight = size.height * 0.05 * heightScale;
      for (var i = 0; i < totalBarsCount; i++) {
        final distanceFromProgress = (i - progressBarIndex).abs();
        final isActive = i < progressBarIndex;

        final double colorIntensity;
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

    // Compensate for audio buffer latency (~150ms typical on mobile)
    final barOffset = 2.35 / peakData.length;
    final adjustedProgress = (progress - barOffset).clamp(0.0, 1.0);
    final progressBarIndex = adjustedProgress * peakData.length;

    for (var i = 0; i < peakData.length; i++) {
      final v = peakData[i];
      final distanceFromProgress = (i - progressBarIndex).abs();
      final isActive = i < progressBarIndex;

      final double colorIntensity;
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

      final animatedHeight =
          calculateWaveformBarHeight(v, size.height) * animationValue;

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
        oldDelegate.isCollapsedPlaceholder != isCollapsedPlaceholder ||
        oldDelegate.progressOverride != progressOverride ||
        oldDelegate.total != total;
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/waveform_service.dart';

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
  late AnimationController _revealController;
  late AnimationController _scrubController;
  late Animation<double> _scrubAnimation;
  Duration _dragOriginDuration = Duration.zero;
  final ValueNotifier<int?> _scrubDeltaNotifier = ValueNotifier<int?>(null);

  double? _dragPosition;
  int? _lastHapticBarIndex;
  StreamSubscription<Duration>? _positionSubscription;
  DateTime? _lastPositionUpdate;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<double?> _dragPositionNotifier = ValueNotifier(null);

  TextStyle? _labelStyle;
  String _formattedTotalTime = '0:00';

  StreamSubscription<List<double>>? _waveformSubscription;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 0.0,
    );
    _scrubController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 0.0,
    );
    _scrubAnimation = CurvedAnimation(
      parent: _scrubController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleWaveformLoad();
    });
    _subscribeToPositionStream();
  }

  @override
  void dispose() {
    _waveformSubscription?.cancel();
    _loadToken++;
    _revealController.dispose();
    _scrubController.dispose();
    _scrubDeltaNotifier.dispose();
    _positionSubscription?.cancel();
    _positionNotifier.dispose();
    _dragPositionNotifier.dispose();
    super.dispose();
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
      _waveformSubscription?.cancel();
      _waveformSubscription = null;
      _positionNotifier.value = Duration.zero;
      _labelStyle = null;
      _peaks = null;
      _revealController.stop();
      _revealController.value = 0.0;

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
    if (widget.filename.isEmpty || widget.path.isEmpty) return;

    final currentFilename = widget.filename;
    final token = ++_loadToken;
    final waveformService = ref.read(waveformServiceProvider);

    // Already decoded this session: paint it immediately with a fast left-to-right sweep
    final inMemory = waveformService.cachedWaveformSync(currentFilename);
    if (inMemory != null && inMemory.isNotEmpty && mounted) {
      setState(() {
        _peaks = inMemory;
      });
      _animateRevealFast();
      return;
    }

    final isCached = await waveformService.isWaveformCached(currentFilename);
    if (!mounted || widget.filename != currentFilename || token != _loadToken) {
      return;
    }

    // Cached on disk: load now with fast sweep
    if (isCached) {
      await _loadWaveform(isCached: true);
      return;
    }

    // Uncached: start decoding in real-time immediately as playback begins
    await _loadWaveform(isCached: false);
  }

  Future<void> _loadWaveform({required bool isCached}) async {
    if (widget.filename.isEmpty || widget.path.isEmpty) return;

    final token = _loadToken;
    final currentFilename = widget.filename;
    final waveformService = ref.read(waveformServiceProvider);

    _waveformSubscription?.cancel();
    _waveformSubscription = waveformService
        .getWaveformProgressive(widget.filename, widget.path, widget.total)
        .listen((peaks) {
      if (!mounted ||
          widget.filename != currentFilename ||
          token != _loadToken) {
        return;
      }

      // Shorter snapshot should never replace a longer one
      if (_peaks != null && peaks.length < _peaks!.length) return;

      setState(() {
        _peaks = peaks;
      });

      if (isCached || peaks.length >= WaveformService.targetWaveformSamples) {
        // Full waveform available: fast left-to-right sweep
        if (_revealController.value < 1.0) {
          if (isCached && _revealController.value == 0.0) {
            _animateRevealFast();
          } else {
            _animateRevealTo(1.0, isComplete: true);
          }
        }
      } else {
        // Progressive CPU decode in real-time: smooth expansion to current fraction
        final target = (peaks.length / WaveformService.targetWaveformSamples)
            .clamp(0.0, 1.0);
        if (target > _revealController.value) {
          _animateRevealTo(target, isComplete: false);
        }
      }
    }, onError: (e) {
      debugPrint('WaveformProgressBar: load failed: $e');
    });
  }

  /// Fast left-to-right sweep for cached waveforms
  void _animateRevealFast() {
    _revealController.stop();
    _revealController.value = 0.0;
    _revealController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  /// Smoothly advances the expansion front as CPU yields new PCM data
  void _animateRevealTo(double target, {required bool isComplete}) {
    final current = _revealController.value;
    if (target <= current) return;
    final delta = (target - current).clamp(0.0, 1.0);
    final int ms;
    final Curve curve;
    if (isComplete) {
      ms = (delta * 350).clamp(120, 240).round();
      curve = Curves.easeOutCubic;
    } else {
      ms = (delta * 500).clamp(80, 200).round();
      curve = Curves.easeOutQuad;
    }
    _revealController.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: curve,
    );
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

  int _calculateBarIndex(double x, double width) {
    final totalBars = (width / 3.0).floor();
    if (totalBars <= 0) return 0;
    return (x.clamp(0.0, width) / 3.0).floor().clamp(0, totalBars - 1);
  }

  void _updateScrubDelta(double targetPercent) {
    if (widget.total.inMilliseconds <= 0) {
      _scrubDeltaNotifier.value = 0;
      return;
    }
    final targetMs = (widget.total.inMilliseconds * targetPercent).round();
    final deltaMs = targetMs - _dragOriginDuration.inMilliseconds;
    final deltaSec = (deltaMs / 1000).round();
    _scrubDeltaNotifier.value = deltaSec;
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
            _dragOriginDuration = _positionNotifier.value;
            _updateScrubDelta(_dragPosition!);
            _scrubController.forward();
            _lastHapticBarIndex = _calculateBarIndex(x, box.size.width);
          },
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx;
            _dragPosition = (x / box.size.width).clamp(0.0, 1.0);
            _dragPositionNotifier.value = _dragPosition;
            _updateScrubDelta(_dragPosition!);
            final currentBar = _calculateBarIndex(x, box.size.width);
            if (_lastHapticBarIndex != null &&
                currentBar != _lastHapticBarIndex) {
              if (ref.read(settingsProvider).waveformHapticsEnabled) {
                HapticFeedback.selectionClick();
              }
            }
            _lastHapticBarIndex = currentBar;
          },
          onHorizontalDragEnd: (details) {
            _lastHapticBarIndex = null;
            _scrubController.reverse();
            if (_dragPosition != null) {
              widget.onSeek(widget.total * _dragPosition!);
            }
            _dragPosition = null;
            _dragPositionNotifier.value = null;
            _scrubDeltaNotifier.value = null;
          },
          onHorizontalDragCancel: () {
            _lastHapticBarIndex = null;
            _scrubController.reverse();
            _dragPosition = null;
            _dragPositionNotifier.value = null;
            _scrubDeltaNotifier.value = null;
          },
          onTapUp: (details) {
            _lastHapticBarIndex = null;
            _scrubController.reverse();
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            _dragPosition = null;
            _dragPositionNotifier.value = null;
            _scrubDeltaNotifier.value = null;
            widget.onSeek(widget.total * percent);
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final x = details.localPosition.dx.clamp(0.0, box.size.width);
            final percent = (x / box.size.width).clamp(0.0, 1.0);
            _dragPosition = percent;
            _dragPositionNotifier.value = percent;
            _dragOriginDuration = _positionNotifier.value;
            _updateScrubDelta(percent);
            _scrubController.forward();
            _lastHapticBarIndex = _calculateBarIndex(x, box.size.width);
          },
          onTapCancel: () {
            _lastHapticBarIndex = null;
            _scrubController.reverse();
            _dragPosition = null;
            _dragPositionNotifier.value = null;
            _scrubDeltaNotifier.value = null;
          },
          child: Container(
            height: 60,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _revealController,
                  builder: (context, child) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: WaveformPainter(
                          peaks: _peaks,
                          revealProgress: _revealController.value,
                          positionNotifier: _positionNotifier,
                          dragPositionNotifier: _dragPositionNotifier,
                          total: widget.total,
                          color: primaryColor,
                        ),
                        isComplex: true,
                        willChange: false,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _scrubAnimation,
          builder: (context, child) {
            final animValue = _scrubAnimation.value;
            final yOffset = animValue * 11.0;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (animValue > 0.01)
                  Positioned(
                    top: -3.0,
                    child: Opacity(
                      opacity: animValue.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.85 + (0.15 * animValue),
                        child: ValueListenableBuilder<int?>(
                          valueListenable: _scrubDeltaNotifier,
                          builder: (context, deltaSec, _) {
                            final delta = deltaSec ?? 0;
                            final deltaText =
                                '${delta >= 0 ? '+' : ''}${delta}s';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                deltaText,
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(0, yOffset),
                  child: Row(
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
                ),
              ],
            );
          },
        ),
      ],
    );
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
  final double revealProgress;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<double?> dragPositionNotifier;
  final Duration total;
  final Color color;

  WaveformPainter({
    required this.peaks,
    required this.revealProgress,
    required this.positionNotifier,
    required this.dragPositionNotifier,
    required this.total,
    required this.color,
  }) : super(
          repaint: Listenable.merge([positionNotifier, dragPositionNotifier]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const spacing = 1.0;
    final totalBarsCount = (size.width / (barWidth + spacing)).floor();
    if (totalBarsCount <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double progress;
    if (dragPositionNotifier.value != null) {
      progress = dragPositionNotifier.value!;
    } else {
      progress = total.inMilliseconds > 0
          ? (positionNotifier.value.inMilliseconds / total.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;
    }

    final inactiveColor = Colors.white.withValues(alpha: 0.18);
    const compressedBarHeight = 2.5;

    final barOffset = 2.35 / totalBarsCount;
    final adjustedProgress = (progress - barOffset).clamp(0.0, 1.0);
    final progressBarIndex = adjustedProgress * totalBarsCount;

    final peakData = peaks;
    final hasPeaks = peakData != null && peakData.isNotEmpty;
    final frontSpan = 3.0 / totalBarsCount;

    for (var i = 0; i < totalBarsCount; i++) {
      final barFraction = (i + 0.5) / totalBarsCount;

      // Reveal factor: 0.0 (compressed baseline) -> 1.0 (fully expanded peak)
      final double revealFactor;
      if (revealProgress <= 0.0 || !hasPeaks) {
        revealFactor = 0.0;
      } else if (revealProgress >= 1.0) {
        revealFactor = 1.0;
      } else if (barFraction >= revealProgress) {
        revealFactor = 0.0;
      } else if (barFraction <= revealProgress - frontSpan) {
        revealFactor = 1.0;
      } else {
        final edgeDelta = (revealProgress - barFraction) / frontSpan;
        revealFactor =
            (edgeDelta * edgeDelta * (3.0 - 2.0 * edgeDelta)).clamp(0.0, 1.0);
      }

      final double targetHeight;
      if (hasPeaks) {
        final samplePos =
            (i / totalBarsCount) * WaveformService.targetWaveformSamples;
        final startIndex = samplePos.floor();
        final endIndex =
            (((i + 1) / totalBarsCount) * WaveformService.targetWaveformSamples)
                .ceil();

        double maxAmp = 0.0;
        if (startIndex < peakData.length) {
          final sliceEnd = math.min(endIndex, peakData.length);
          for (var s = startIndex; s < sliceEnd; s++) {
            if (peakData[s] > maxAmp) maxAmp = peakData[s];
          }
          if (maxAmp == 0.0 && startIndex < peakData.length) {
            maxAmp = peakData[startIndex];
          }
        }
        targetHeight = calculateWaveformBarHeight(maxAmp, size.height);
      } else {
        targetHeight = compressedBarHeight;
      }

      final barHeight =
          ui.lerpDouble(compressedBarHeight, targetHeight, revealFactor)!;

      final distanceFromProgress = (i - progressBarIndex).abs();
      final isActive = i < progressBarIndex;

      final Color baseColor;
      if (distanceFromProgress >= 2) {
        baseColor = isActive ? color : inactiveColor;
      } else {
        final colorIntensity = isActive ? 1.0 : (2 - distanceFromProgress) / 2;
        baseColor = Color.lerp(inactiveColor, color, colorIntensity)!;
      }

      // Subtle opacity scaling for compressed bars ahead of the generation front
      final double alphaScale = ui.lerpDouble(0.65, 1.0, revealFactor)!;
      paint.color = baseColor.withValues(
          alpha: (baseColor.a * alphaScale).clamp(0.0, 1.0));

      final x = i * (barWidth + spacing) + spacing / 2;
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          y,
          x + barWidth,
          y + barHeight,
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.color != color ||
        oldDelegate.total != total;
  }
}

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class BasicProgressBar extends StatefulWidget {
  final AudioPlayer player;
  final Duration total;
  final Function(Duration) onSeek;

  const BasicProgressBar({
    super.key,
    required this.player,
    required this.total,
    required this.onSeek,
  });

  @override
  State<BasicProgressBar> createState() => _BasicProgressBarState();
}

class _BasicProgressBarState extends State<BasicProgressBar> {
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<double> _dragProgressNotifier = ValueNotifier(0.0);
  bool _isDragging = false;
  String _formattedTotalTime = '';

  @override
  void initState() {
    super.initState();
    _positionNotifier.value = widget.player.position;
    _formattedTotalTime = _formatDuration(widget.total);

    widget.player.playerStateStream.listen((state) {
      if (mounted && state.playing) {
        _startUpdating();
      }
    });
  }

  void _startUpdating() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted && widget.player.playing && !_isDragging) {
        _positionNotifier.value = widget.player.position;
        return true;
      }
      return false;
    });
  }

  @override
  void didUpdateWidget(BasicProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total != widget.total) {
      _formattedTotalTime = _formatDuration(widget.total);
    }
    if (oldWidget.player != widget.player) {
      _positionNotifier.value = widget.player.position;
    }
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    _dragProgressNotifier.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  void _onDragStart(double progress) {
    setState(() {
      _isDragging = true;
    });
    _dragProgressNotifier.value = progress;
  }

  void _onDragUpdate(double progress) {
    _dragProgressNotifier.value = progress;
  }

  void _onDragEnd() {
    widget.onSeek(widget.total * _dragProgressNotifier.value);
    setState(() {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressBar(
          height: 60,
          positionNotifier: _positionNotifier,
          dragProgressNotifier: _dragProgressNotifier,
          isDragging: _isDragging,
          total: widget.total,
          primaryColor: primaryColor,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          onSeek: widget.onSeek,
        ),
        const SizedBox(height: 8),
        _TimeDisplay(
          positionNotifier: _positionNotifier,
          dragProgressNotifier: _dragProgressNotifier,
          isDragging: _isDragging,
          total: widget.total,
          formattedTotalTime: _formattedTotalTime,
          theme: theme,
        ),
      ],
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<double> dragProgressNotifier;
  final bool isDragging;
  final Duration total;
  final String formattedTotalTime;
  final ThemeData theme;

  const _TimeDisplay({
    required this.positionNotifier,
    required this.dragProgressNotifier,
    required this.isDragging,
    required this.total,
    required this.formattedTotalTime,
    required this.theme,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: dragProgressNotifier,
      builder: (context, dragProgress, _) {
        if (isDragging) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(total * dragProgress),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                formattedTotalTime,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          );
        }
        return ValueListenableBuilder<Duration>(
          valueListenable: positionNotifier,
          builder: (context, position, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  formattedTotalTime,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ProgressBar extends StatefulWidget {
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<double> dragProgressNotifier;
  final bool isDragging;
  final Duration total;
  final double height;
  final Color primaryColor;
  final Function(double) onDragStart;
  final Function(double) onDragUpdate;
  final VoidCallback onDragEnd;
  final Function(Duration) onSeek;

  const _ProgressBar({
    required this.positionNotifier,
    required this.dragProgressNotifier,
    required this.isDragging,
    required this.total,
    required this.height,
    required this.primaryColor,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onSeek,
  });

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        final box = context.findRenderObject() as RenderBox;
        final x = details.localPosition.dx;
        final progress = (x / box.size.width).clamp(0.0, 1.0);
        widget.onDragStart(progress);
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final x = details.localPosition.dx;
        final progress = (x / box.size.width).clamp(0.0, 1.0);
        widget.onDragUpdate(progress);
      },
      onHorizontalDragEnd: (_) {
        widget.onDragEnd();
      },
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox;
        final x = details.localPosition.dx.clamp(0.0, box.size.width);
        final progress = (x / box.size.width).clamp(0.0, 1.0);
        widget.onSeek(widget.total * progress);
      },
      child: ValueListenableBuilder<Duration>(
        valueListenable: widget.positionNotifier,
        builder: (context, position, _) {
          final progress = widget.total.inMilliseconds > 0
              ? (position.inMilliseconds / widget.total.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 0.0;

          return ValueListenableBuilder<double>(
            valueListenable: widget.dragProgressNotifier,
            builder: (context, dragProgress, _) {
              final displayProgress =
                  widget.isDragging ? dragProgress : progress;

              return CustomPaint(
                size: Size(double.infinity, widget.height),
                painter: _ProgressBarPainter(
                  progress: displayProgress,
                  height: widget.height,
                  primaryColor: widget.primaryColor,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final double height;
  final Color primaryColor;

  _ProgressBarPainter({
    required this.progress,
    required this.height,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    final progressPaint = Paint()
      ..color = primaryColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final trackWidth = size.width;

    // Draw background track
    canvas.drawLine(
      Offset(0, centerY),
      Offset(trackWidth, centerY),
      trackPaint,
    );

    // Draw progress
    final progressWidth = trackWidth * progress;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(progressWidth, centerY),
      progressPaint,
    );

    // Draw thumb
    if (progressWidth > 0) {
      canvas.drawCircle(Offset(progressWidth, centerY), 6, thumbPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

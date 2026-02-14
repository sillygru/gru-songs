import 'package:flutter/material.dart';

class BasicProgressBar extends StatefulWidget {
  final Duration progress;
  final Duration total;
  final Function(Duration) onSeek;

  const BasicProgressBar({
    super.key,
    required this.progress,
    required this.total,
    required this.onSeek,
  });

  @override
  State<BasicProgressBar> createState() => _BasicProgressBarState();
}

class _BasicProgressBarState extends State<BasicProgressBar> {
  bool _isDragging = false;
  double? _dragValue;

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
    final theme = Theme.of(context);
    final progress = _isDragging && _dragValue != null
        ? _dragValue!
        : (widget.total.inMilliseconds > 0
            ? (widget.progress.inMilliseconds / widget.total.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 60,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.white,
              overlayColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: progress,
              onChanged: (value) {
                setState(() {
                  _isDragging = true;
                  _dragValue = value;
                });
              },
              onChangeEnd: (value) {
                widget.onSeek(widget.total * value);
                setState(() {
                  _isDragging = false;
                  _dragValue = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(_isDragging && _dragValue != null
                  ? widget.total * _dragValue!
                  : widget.progress),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              _formatDuration(widget.total),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
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

import 'dart:math';
import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  final Color color;
  final double width;
  final double height;
  final bool isPlaying;

  const AudioVisualizer({
    super.key,
    this.color = Colors.white,
    this.width = 24,
    this.height = 24,
    this.isPlaying = true,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = [0.2, 0.5, 0.8, 0.4];
  final List<double> _targetHeights = [0.8, 0.2, 0.5, 0.9];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() {
        if (widget.isPlaying) {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              // Move current height towards target
              _barHeights[i] =
                  _barHeights[i] + (_targetHeights[i] - _barHeights[i]) * 0.2;

              // If close to target, pick a new target
              if ((_targetHeights[i] - _barHeights[i]).abs() < 0.1) {
                _targetHeights[i] = _random.nextDouble() * 0.8 + 0.2;
              }
            }
          });
        }
      });

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
        setState(() {
          _barHeights.fillRange(0, _barHeights.length, 0.3);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_barHeights.length, (index) {
            return Container(
              width: widget.width / (_barHeights.length * 2),
              height: widget.height * _barHeights[index],
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}

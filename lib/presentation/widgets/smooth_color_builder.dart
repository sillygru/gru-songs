import 'package:flutter/material.dart';

class SmoothColorBuilder extends StatefulWidget {
  final Color targetColor;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, Color color) builder;

  const SmoothColorBuilder({
    super.key,
    required this.targetColor,
    required this.builder,
    this.duration = const Duration(milliseconds: 1420),
    this.curve = Curves.easeInOutCubic,
  });

  @override
  State<SmoothColorBuilder> createState() => _SmoothColorBuilderState();
}

class _SmoothColorBuilderState extends State<SmoothColorBuilder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _animation;
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.targetColor;
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = AlwaysStoppedAnimation(widget.targetColor);
  }

  @override
  void didUpdateWidget(SmoothColorBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetColor != widget.targetColor) {
      _animation = ColorTween(
        begin: _currentColor,
        end: widget.targetColor,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        _currentColor = _animation.value ?? widget.targetColor;
        return widget.builder(context, _currentColor);
      },
    );
  }
}

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

class _BarsModel extends ChangeNotifier {
  final List<double> _barHeights;
  final List<double> _targetHeights;
  final Random _random;

  _BarsModel({
    required int barCount,
    required Random random,
  })  : _barHeights = List<double>.filled(barCount, 0.2),
        _targetHeights = List<double>.filled(barCount, 0.5),
        _random = random {
    for (var i = 0; i < _barHeights.length; i++) {
      _targetHeights[i] = _random.nextDouble() * 0.8 + 0.2;
    }
  }

  List<double> get barHeights => _barHeights;

  void tick({required bool isPlaying, required bool isAppActive}) {
    if (!isPlaying || !isAppActive) {
      // Don't notify when idle, but keep the static heights so the
      // last-rendered frame is preserved.
      return;
    }
    for (int i = 0; i < _barHeights.length; i++) {
      _barHeights[i] =
          _barHeights[i] + (_targetHeights[i] - _barHeights[i]) * 0.2;
      if ((_targetHeights[i] - _barHeights[i]).abs() < 0.1) {
        _targetHeights[i] = _random.nextDouble() * 0.8 + 0.2;
      }
    }
    notifyListeners();
  }

  void reset(double value) {
    for (int i = 0; i < _barHeights.length; i++) {
      _barHeights[i] = value;
    }
    notifyListeners();
  }
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _targetFrameInterval = Duration(milliseconds: 16);
  static const int _barCount = 4;

  late AnimationController _controller;
  late _BarsModel _bars;
  bool _isAppActive = true;
  Duration? _lastVisualUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bars = _BarsModel(barCount: _barCount, random: Random());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(_onControllerTick);

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  void _onControllerTick() {
    final elapsed = _controller.lastElapsedDuration;
    if (elapsed == null) return;
    if (_lastVisualUpdate != null &&
        elapsed - _lastVisualUpdate! < _targetFrameInterval) {
      return;
    }
    _lastVisualUpdate = elapsed;

    _bars.tick(
      isPlaying: widget.isPlaying,
      isAppActive: _isAppActive,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isActive = state == AppLifecycleState.resumed;
    if (_isAppActive != isActive) {
      _isAppActive = isActive;
      if (isActive && widget.isPlaying) {
        if (!_controller.isAnimating) {
          _lastVisualUpdate = null;
          _controller.repeat();
        }
      } else {
        if (_controller.isAnimating) {
          _controller.stop();
        }
        _lastVisualUpdate = null;
      }
    }
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying && _isAppActive) {
        _lastVisualUpdate = null;
        _controller.repeat();
      } else {
        _controller.stop();
        _lastVisualUpdate = null;
        _bars.reset(0.3);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerTick);
    _controller.dispose();
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      // AnimatedBuilder only rebuilds the bar row on each frame, not the
      // outer widget tree, so it skips the parent State.build that
      // setState() would force.
      child: ListenableBuilder(
        listenable: _bars,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_barCount, (index) {
              return Container(
                width: widget.width / (_barCount * 2),
                height: widget.height * _bars.barHeights[index],
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

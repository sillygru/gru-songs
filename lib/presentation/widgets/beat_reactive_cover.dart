import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_energy_provider.dart';

class BeatReactiveCover extends ConsumerStatefulWidget {
  final Widget child;

  const BeatReactiveCover({super.key, required this.child});

  @override
  ConsumerState<BeatReactiveCover> createState() => _BeatReactiveCoverState();
}

class _BeatReactiveCoverState extends ConsumerState<BeatReactiveCover>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.97;
  static const double _maxScale = 1.08;
  static const double _beatPeakScale = 1.06;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: _beatPeakScale)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: _beatPeakScale, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 300,
      ),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AudioEnergyState>(audioEnergyProvider, (previous, next) {
      if (next.beatPulse &&
          previous?.beatPulse != true &&
          next.isPlaying) {
        _pulseController.forward(from: 0);
      }
    });
    final energy = ref.watch(audioEnergyProvider);

    final idleScale = 1.0 + (energy.energy * 0.02);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale = _pulseAnimation.value;
        final combined =
            (idleScale * pulseScale).clamp(_minScale, _maxScale);
        return Transform.scale(
          scale: combined,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

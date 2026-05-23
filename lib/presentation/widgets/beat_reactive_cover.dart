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
  static const double _baseIdleScale = 0.95;
  static const double _maxBreathingBonus = 0.06;
  static const double _maxBeatPunch = 0.12;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: _maxBeatPunch)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 5, // Instant forward punch (~9ms)
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: _maxBeatPunch, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)), // Fixed valid snappy curve
        weight: 95,
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
    final energyState = ref.watch(audioEnergyProvider);

    ref.listen<AudioEnergyState>(audioEnergyProvider, (previous, next) {
      if (next.beatPulse && previous?.beatPulse != true && next.isPlaying) {
        _pulseController.forward(from: 0);
      }
    });

    final dynamicBreathing = _baseIdleScale + (energyState.energy * _maxBreathingBonus);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final totalScale = dynamicBreathing + _pulseAnimation.value;

        return Transform.scale(
          scale: totalScale,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_energy_provider.dart';

class SoundReactiveParticles extends ConsumerStatefulWidget {
  final Color baseColor;

  const SoundReactiveParticles({super.key, required this.baseColor});

  @override
  ConsumerState<SoundReactiveParticles> createState() =>
      _SoundReactiveParticlesState();
}

class _SoundReactiveParticlesState extends ConsumerState<SoundReactiveParticles>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _random = Random();
  late List<_Particle> _particles;
  double _beatBoost = 0;
  int _frame = 0;
  AudioEnergyState _energy = AudioEnergyState.idle;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _particles = _createParticles(24);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetCount = _particleCount(context);
    if (_particles.length != targetCount) {
      _particles = _createParticles(targetCount);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }

  int _particleCount(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr >= 3) return 40;
    if (dpr >= 2) return 32;
    return 24;
  }

  List<_Particle> _createParticles(int count) {
    return List.generate(count, (index) {
      return _Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 0.7,
        vx: (_random.nextDouble() - 0.5) * 0.0015,
        vy: (_random.nextDouble() - 0.7) * 0.0015,
        baseSize: 2.5 + _random.nextDouble() * 4,
        mass: 0.6 + _random.nextDouble() * 0.8,
        phase: _random.nextDouble() * pi * 2,
        lightnessOffset: (_random.nextDouble() - 0.5) * 0.18,
      );
    });
  }

  void _onTick(Duration elapsed) {
    final energy = ref.read(audioEnergyProvider);
    if (energy.beatPulse && energy.isPlaying) {
      _beatBoost = 1;
    } else {
      _beatBoost *= 0.9;
    }
    _energy = energy;
    _updateParticles();
    _frame++;
    if (!_disposed && mounted) setState(() {});
  }

  static const double _gravity = 0.00018;

  void _updateParticles() {
    final energyBoost = _energy.energy * 0.65 + _beatBoost * 0.35;
    final isBeat = _energy.beatPulse && _energy.isPlaying;

    for (final particle in _particles) {
      // Gravity — heavier particles fall slightly slower
      particle.vy += _gravity / particle.mass;

      // Brownian drift scaled by energy
      particle.vx +=
          (_random.nextDouble() - 0.5) * 0.00008 * energyBoost / particle.mass;
      particle.vy +=
          (_random.nextDouble() - 0.5) * 0.00008 * energyBoost / particle.mass;

      // Beat burst — strong upward kick with sideways scatter
      if (isBeat) {
        particle.vx +=
            (_random.nextDouble() - 0.5) * 0.0035 / particle.mass;
        particle.vy -= _random.nextDouble() * 0.006 / particle.mass;
      }

      // Apply velocity
      particle.x += particle.vx;
      particle.y += particle.vy;

      // Bounce off edges with energy loss
      if (particle.x < 0) {
        particle.x = -particle.x;
        particle.vx = -particle.vx * 0.55;
      } else if (particle.x > 1) {
        particle.x = 2 - particle.x;
        particle.vx = -particle.vx * 0.55;
      }
      if (particle.y < 0) {
        particle.y = -particle.y;
        particle.vy = -particle.vy * 0.45;
      } else if (particle.y > 1) {
        particle.y = 2 - particle.y;
        particle.vy = -particle.vy * 0.45;
      }

      // Drag
      particle.vx *= 0.992;
      particle.vy *= 0.992;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ParticlesPainter(
          particles: _particles,
          baseColor: widget.baseColor,
          energy: _energy.energy,
          beatBoost: _beatBoost,
          frame: _frame,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  final double baseSize;
  final double mass;
  final double phase;
  final double lightnessOffset;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.baseSize,
    required this.mass,
    required this.phase,
    required this.lightnessOffset,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final Color baseColor;
  final double energy;
  final double beatBoost;
  final int frame;

  _ParticlesPainter({
    required this.particles,
    required this.baseColor,
    required this.energy,
    required this.beatBoost,
    required this.frame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    for (final particle in particles) {
      final hsl = HSLColor.fromColor(baseColor);
      final color = hsl
          .withLightness(
              (hsl.lightness + particle.lightnessOffset).clamp(0.15, 0.85))
          .toColor();

      final radius = particle.baseSize *
          (0.85 + energy * 0.55 + beatBoost * 0.45) *
          (size.shortestSide / 360);
      final opacity =
          (0.14 + energy * 0.22 + beatBoost * 0.18 + sin(particle.phase) * 0.04)
              .clamp(0.08, 0.55);

      final center = Offset(particle.x * size.width, particle.y * size.height);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.energy != energy ||
        oldDelegate.beatBoost != beatBoost ||
        oldDelegate.baseColor != baseColor;
  }
}

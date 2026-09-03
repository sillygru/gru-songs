import 'package:flutter/widgets.dart';

import '../../domain/models/beat_map.dart';
import '../../models/song.dart';
import '../widgets/player_motion.dart';

/// Deep module that collapses the player visual ensemble's throttling
/// into one scheduler.
///
/// Before: five independent throttlers drift — `PlayerMotionController`
/// at 60/30Hz, `BeatCoverGlow` at 30Hz (32-step quant), `BeatParticleField`
/// at 60/30Hz, `_ThrottledSpin` at 15Hz, and `DisplayRefreshService`
/// boosting to 120Hz. Retuning one breaks perceptual sync because glow
/// snap (≈32 levels) moves at a different granularity than surge
/// `Δv·τ≈4.5%`.
///
/// This module is the single place that owns the ticker and exposes one
/// `Listenable<BeatFrame>` plus one `decorativeRepaint` that all widgets
/// share. Widgets become stateless adapters over the ensemble's
/// interface, giving the ensemble locality and leverage: one budget,
/// N consumers, one test surface.
///
/// Two adapters justify the seam: the real ticker (prod on device) and
/// an in-memory fake driven by `debugTick` in tests.
class PlayerMotionEnsemble extends ChangeNotifier {
  final PlayerMotionController _controller;

  PlayerMotionEnsemble({required PlayerMotionController controller})
      : _controller = controller {
    _controller.addListener(_forward);
    _controller.decorativeRepaint.addListener(_forwardDecorative);
  }

  /// Shared controller so callers that already own one can wrap it.
  factory PlayerMotionEnsemble.wrap(PlayerMotionController controller) =>
      PlayerMotionEnsemble(controller: controller);

  BeatFrame get frame => _controller.frame;
  MotionIntensitySpec get coverSpec => _controller.coverSpec;
  MotionIntensitySpec get particleSpec => _controller.particleSpec;
  bool get hasBeatMap => _controller.hasBeatMap;
  Duration get elapsed => _controller.elapsed;

  /// Single scheduler—cover and decorative share the same clock.
  Listenable get frameListenable => this;
  Listenable get decorativeRepaint => _controller.decorativeRepaint;

  void attach(TickerProvider vsync) => _controller.attach(vsync);

  set beatMap(BeatMap? map) => _controller.beatMap = map;
  set coverIntensity(PlayerMotionIntensity v) => _controller.coverIntensity = v;
  set particleIntensity(PlayerMotionIntensity v) =>
      _controller.particleIntensity = v;
  set coverCustomIntensity(double v) => _controller.coverCustomIntensity = v;
  set particleCustomIntensity(double v) =>
      _controller.particleCustomIntensity = v;
  set latencyMs(int v) => _controller.latencyMs = v;
  set enabled(bool v) => _controller.enabled = v;
  set appActive(bool v) => _controller.appActive = v;
  set powerSave(bool v) => _controller.powerSave = v;

  void _forward() => notifyListeners();
  void _forwardDecorative() {
    // decorative repaint is separate listenable; no need to forward here
  }

  @override
  void dispose() {
    _controller.removeListener(_forward);
    _controller.decorativeRepaint.removeListener(_forwardDecorative);
    _controller.dispose();
    super.dispose();
  }
}

/// In-memory fake for tests — no ticker, no platform.
class FakePlayerMotionEnsemble extends ChangeNotifier {
  BeatFrame frame = BeatFrame.idle;
  MotionIntensitySpec coverSpec =
      MotionIntensitySpec.of(PlayerMotionIntensity.balanced);
  MotionIntensitySpec particleSpec =
      MotionIntensitySpec.of(PlayerMotionIntensity.balanced);

  final ChangeNotifier decorativeRepaint = ChangeNotifier();

  void debugTick(Duration elapsed, double positionMs, BeatMap? map) {
    // minimal: produce a pulse based on position without real BeatMap math
    frame = BeatFrame(
      pulse: (positionMs % 500) < 50 ? 0.8 : 0.0,
      breath: 0.3,
      hasBeat: map?.hasBeats ?? false,
    );
    notifyListeners();
    decorativeRepaint.notifyListeners();
  }

  @override
  void dispose() {
    decorativeRepaint.dispose();
    super.dispose();
  }
}

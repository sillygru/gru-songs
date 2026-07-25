import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/models/beat_map.dart';
import '../../domain/services/playhead_clock.dart';
import '../../domain/services/spectrum_bars.dart';
import '../../models/song.dart';
import '../../services/beat_analysis_service.dart';
import '../../services/power_state_service.dart';

/// Drives every [AudioVisualizer] in the app from one ticker.
///
/// The bars show up in the now-playing bar, in song lists and in the queue, and
/// more than one of them is on screen at a time. Each used to run its own
/// `AnimationController` and its own `Random`; now the frame math happens once
/// here and every mounted visualiser paints the same four numbers. Published as
/// a [ChangeNotifier] rather than through Riverpod, matching how playback state
/// is handled elsewhere: the listeners are painters, not the provider graph.
///
/// In [VisualizerMode.synced] the levels come from the current track's
/// [BeatMap] — the same precomputed analysis that drives the player's cover —
/// sampled at the playhead. Left to right the bars are bass, low-mid, mid and
/// air. Nothing here does DSP; the expensive part happened once, offline.
///
/// Idle by construction: with no listeners it holds no ticker and no stream
/// subscriptions at all.
class SpectrumController extends ChangeNotifier {
  /// Shortest gap between emitted frames, at normal power and in power-save.
  /// Same cap, and the same reasoning, as `PlayerMotionController`.
  static const Duration _frameInterval = Duration(microseconds: 16667);
  static const Duration _powerSaveFrameInterval = Duration(microseconds: 33333);

  /// Time constant of the idle random walk, chosen to match the feel of the old
  /// per-widget animation (a 0.2 lerp every 16 ms).
  static const double _idleTau = 0.072;

  /// How long the bars take to hand over from the idle walk to the beat grid.
  /// Analysis lands mid-track, and without this the bars visibly jump.
  static const double _gridBlendMs = 400;

  /// Longest step the ballistics will integrate in one go. A frame that arrives
  /// after the app was busy elsewhere should not teleport the bars.
  static const double _maxStepSeconds = 0.1;

  final AudioPlayer? _player;
  final ValueListenable<Song?>? _currentSong;
  final BeatAnalysisService? _beatAnalysis;

  final PlayheadClock _clock = PlayheadClock();

  /// Bar heights in 0..1, low frequencies first. Read by the painter every
  /// frame; never reallocated.
  final Float64List levels = Float64List(SpectrumBars.barCount)
    ..fillRange(0, SpectrumBars.barCount, SpectrumBars.floor);

  final List<double> _syncedTargets =
      List<double>.filled(SpectrumBars.barCount, SpectrumBars.floor);
  final List<double> _idleTargets =
      List<double>.filled(SpectrumBars.barCount, 0.5);
  final math.Random _random = math.Random();

  VisualizerMode _mode = VisualizerMode.synced;
  BeatMap? _beatMap;
  String? _beatMapFilename;
  int _beatMapToken = 0;
  double _gridBlend = 0;

  Ticker? _ticker;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  _LifecycleObserver? _observer;

  bool _wired = false;
  bool _appActive = true;
  Duration _minFrameInterval = _frameInterval;
  Duration _elapsed = Duration.zero;
  Duration? _lastEmitted;

  SpectrumController({
    required AudioPlayer player,
    required ValueListenable<Song?> currentSong,
    required BeatAnalysisService beatAnalysis,
  })  : _player = player,
        _currentSong = currentSong,
        _beatAnalysis = beatAnalysis;

  /// Detached from the player and the analysis service, for driving frames by
  /// hand in tests.
  @visibleForTesting
  SpectrumController.forTesting()
      : _player = null,
        _currentSong = null,
        _beatAnalysis = null;

  VisualizerMode get mode => _mode;

  set mode(VisualizerMode value) {
    if (_mode == value) return;
    _mode = value;
    if (value != VisualizerMode.synced) {
      _beatMap = null;
      _beatMapFilename = null;
      _gridBlend = 0;
    }
    _syncWiring();
    if (_wired) _loadBeatMap();
  }

  /// Output-latency compensation, shared with the player's motion setting — the
  /// bars and the cover are answering the same audio.
  set latencyMs(int value) => _clock.latencyMs = value;

  /// True once a beat grid is driving the bars, as opposed to the idle walk.
  bool get isSynced => _gridBlend > 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncWiring();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncWiring();
  }

  /// Attaches to (or detaches from) the player, the analysis service and the
  /// ticker, based on whether anything is actually watching.
  void _syncWiring() {
    final shouldWire =
        hasListeners && _mode != VisualizerMode.off && _player != null;
    if (shouldWire == _wired) return;
    _wired = shouldWire;

    if (shouldWire) {
      final player = _player!;
      _clock
        ..reset(player.position)
        ..playing = player.playing;
      _positionSub = player.positionStream.listen(_clock.onPosition);
      _stateSub = player.playerStateStream.listen(_onPlayerState);
      _currentSong?.addListener(_loadBeatMap);
      PowerStateService.instance.powerSave.addListener(_onPowerSave);
      _onPowerSave();
      _observer = _LifecycleObserver(_onLifecycle);
      WidgetsBinding.instance.addObserver(_observer!);
      _ticker ??= Ticker(_onTick, debugLabel: 'SpectrumController');
      _loadBeatMap();
    } else {
      _positionSub?.cancel();
      _positionSub = null;
      _stateSub?.cancel();
      _stateSub = null;
      _currentSong?.removeListener(_loadBeatMap);
      PowerStateService.instance.powerSave.removeListener(_onPowerSave);
      if (_observer != null) {
        WidgetsBinding.instance.removeObserver(_observer!);
        _observer = null;
      }
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
      _lastEmitted = null;
      _beatMapToken++;
      _resetLevels();
    }
    _syncTicker();
  }

  void _onPlayerState(PlayerState state) {
    if (_clock.playing == state.playing) return;
    _clock.playing = state.playing;
    _syncTicker();
  }

  void _onLifecycle(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    _syncTicker();
  }

  void _onPowerSave() {
    _minFrameInterval = PowerStateService.instance.powerSave.value
        ? _powerSaveFrameInterval
        : _frameInterval;
  }

  void _syncTicker() {
    final ticker = _ticker;
    if (ticker == null) return;

    final shouldRun = _wired && _clock.playing && _appActive;
    if (shouldRun && !ticker.isActive) {
      _lastEmitted = null;
      ticker.start();
    } else if (!shouldRun && ticker.isActive) {
      ticker.stop();
      // Settle to rest rather than freezing mid-punch.
      _resetLevels();
      _lastEmitted = null;
      notifyListeners();
    }
  }

  void _resetLevels() {
    levels.fillRange(0, SpectrumBars.barCount, SpectrumBars.floor);
    _syncedTargets.fillRange(0, SpectrumBars.barCount, SpectrumBars.floor);
  }

  /// Loads the beat map for whatever is playing now.
  ///
  /// Cache first, so an already-analysed track locks on instantly; only then
  /// analysis, during which the bars keep running the idle walk. Mirrors what
  /// the player screen does, and shares its de-duplicated service, so opening
  /// the player on a track the bars already requested costs nothing extra.
  Future<void> _loadBeatMap() async {
    if (!_wired || _mode != VisualizerMode.synced) return;
    final service = _beatAnalysis;
    final song = _currentSong?.value;
    if (service == null) return;

    if (song == null) {
      _beatMapFilename = null;
      _beatMap = null;
      _gridBlend = 0;
      _beatMapToken++;
      return;
    }
    if (song.filename == _beatMapFilename) return;

    _beatMapFilename = song.filename;
    final token = ++_beatMapToken;
    _beatMap = null;
    _gridBlend = 0;

    final cached = await service.readCached(song.filename);
    if (token != _beatMapToken) return;
    if (cached != null) {
      _beatMap = cached.hasBands ? cached : null;
      return;
    }

    final analyzed = await service.analyze(song.filename, song.url);
    if (token != _beatMapToken) return;
    _beatMap = (analyzed?.hasBands ?? false) ? analyzed : null;
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;

    final last = _lastEmitted;
    if (last != null) {
      if (_elapsed - last < _minFrameInterval) return;
    }
    final dt = last == null
        ? 1 / 60
        : math.min((_elapsed - last).inMicroseconds / 1e6, _maxStepSeconds);
    _lastEmitted = _elapsed;

    advance(dt, _clock.visualPositionMs);
    notifyListeners();
  }

  /// Advances the bars by [dtSeconds] at [positionMs]. Separated from the
  /// ticker so tests can step through it deterministically.
  @visibleForTesting
  void advance(double dtSeconds, double positionMs) {
    _rollIdleTargets();

    final map = _beatMap;
    final synced = _mode == VisualizerMode.synced &&
        map != null &&
        SpectrumBars.targetsAt(map, positionMs, _syncedTargets);

    if (synced) {
      _gridBlend =
          (_gridBlend + dtSeconds * 1000 / _gridBlendMs).clamp(0.0, 1.0);
    } else if (_gridBlend > 0) {
      _gridBlend =
          (_gridBlend - dtSeconds * 1000 / _gridBlendMs).clamp(0.0, 1.0);
    }

    final elapsedSeconds = _elapsed.inMicroseconds / 1e6;
    for (var i = 0; i < SpectrumBars.barCount; i++) {
      var target = _idleTargets[i];
      if (_gridBlend > 0) {
        final band = _syncedTargets[i] * SpectrumBars.breath(i, elapsedSeconds);
        target = target + (band - target) * _gridBlend;
      }
      // Cross-fade the response along with the targets: the idle walk has one
      // time constant in both directions, the synced bars snap up and glide
      // down. Switching filters in one frame is visible; sliding between them
      // is not.
      final asymmetric = SpectrumBars.tauFor(levels[i], target);
      final tau = _gridBlend <= 0
          ? _idleTau
          : _idleTau + (asymmetric - _idleTau) * _gridBlend;
      levels[i] = SpectrumBars.advanceWithTau(levels[i], target, dtSeconds, tau)
          .clamp(0.0, 1.0);
    }
  }

  /// The old visualiser's motion, kept for [VisualizerMode.classic] and used as
  /// the fallback while a track is still being analysed: walk toward a random
  /// target, pick a new one on arrival. Only the target selection is random —
  /// the walk itself rides the shared ballistics in [advance].
  void _rollIdleTargets() {
    // Not worth rolling when the grid has fully taken over the output.
    if (_gridBlend >= 1) return;
    for (var i = 0; i < SpectrumBars.barCount; i++) {
      if ((_idleTargets[i] - levels[i]).abs() < 0.1) {
        _idleTargets[i] = _random.nextDouble() * 0.8 + 0.2;
      }
    }
  }

  @visibleForTesting
  set debugBeatMap(BeatMap? map) => _beatMap = map;

  @visibleForTesting
  void debugSetMode(VisualizerMode value) => _mode = value;

  @visibleForTesting
  bool get debugWired => _wired;

  @visibleForTesting
  bool get debugTicking => _ticker?.isActive ?? false;

  @visibleForTesting
  double get debugGridBlend => _gridBlend;

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _currentSong?.removeListener(_loadBeatMap);
    PowerStateService.instance.powerSave.removeListener(_onPowerSave);
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    // Ticker.dispose asserts it is not still running, which is exactly the case
    // when the last visualiser goes away mid-playback.
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// The controller is not a widget, so it cannot mix in [WidgetsBindingObserver]
/// without also inheriting a pile of no-op callbacks. One small adapter instead.
class _LifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState) onChange;

  _LifecycleObserver(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

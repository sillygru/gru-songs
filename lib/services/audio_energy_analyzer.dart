import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'waveform_service.dart';

class AudioEnergyState {
  final double energy;
  final bool beatPulse;
  final bool isPlaying;

  const AudioEnergyState({
    this.energy = 0,
    this.beatPulse = false,
    this.isPlaying = false,
  });

  static const idle = AudioEnergyState();
}

/// Samples cached waveform peaks at the playhead to approximate live energy.
class AudioEnergyAnalyzer with WidgetsBindingObserver {
  AudioEnergyAnalyzer({
    required AudioPlayer player,
    required WaveformService waveformService,
    required Future<String?> Function() resolveCurrentSongPath,
    required Future<String?> Function() resolveCurrentSongFilename,
  })  : _player = player,
        _waveformService = waveformService,
        _resolveCurrentSongPath = resolveCurrentSongPath,
        _resolveCurrentSongFilename = resolveCurrentSongFilename;

  final AudioPlayer _player;
  final WaveformService _waveformService;
  final Future<String?> Function() _resolveCurrentSongPath;
  final Future<String?> Function() _resolveCurrentSongFilename;

  static const Duration _sampleInterval = Duration(milliseconds: 20);
  static const int _historySize = 10;
  static const double _beatMultiplier = 1.06;

  final _controller = StreamController<AudioEnergyState>.broadcast();
  final Queue<double> _energyHistory = Queue<double>();

  Stream<AudioEnergyState> get stream => _controller.stream;

  List<double> _waveform = const [];
  String? _loadedFilename;
  int _loadToken = 0;
  bool _isAppActive = true;
  bool _isPlaying = false;
  bool _running = false;
  Timer? _timer;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<SequenceState?>? _sequenceSub;
  double _smoothedEnergy = 0;
  double _baselineEnergy = 0;
  double _visualEnergy = 0;

  // Prevents frame double-triggering on single messy sound peaks
  int _ticksSinceLastBeat = 0;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _sequenceSub = _player.sequenceStateStream.listen((_) {
      unawaited(_loadWaveformForCurrentTrack());
    });
    _onPlayerState(_player.playerState);
    unawaited(_loadWaveformForCurrentTrack());
    // _onPlayerState decides whether the timer is needed; do not start it
    // unconditionally here or we will keep ticking while paused.
    if (_isPlaying) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(_sampleInterval, (_) => _tick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _stopTimer();
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _sequenceSub?.cancel();
    _sequenceSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _energyHistory.clear();
    _smoothedEnergy = 0;
    _baselineEnergy = 0;
    _visualEnergy = 0;
    _ticksSinceLastBeat = 0;
    _emit(const AudioEnergyState());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isActive = state == AppLifecycleState.resumed;
    if (_isAppActive == isActive) return;
    _isAppActive = isActive;
    if (!isActive) {
      // Avoid burning a 20ms tick in the background. Resume when foregrounded
      // and the player is actively playing.
      _stopTimer();
      _emit(const AudioEnergyState());
    } else if (_isPlaying) {
      _startTimer();
    }
  }

  void _onPlayerState(PlayerState state) {
    if (!_running) return;
    _isPlaying = state.playing;
    if (!state.playing) {
      // Pause-driven timer shutdown: the next 20ms tick would just decay and
      // emit zeros, which is wasteful while paused.
      _stopTimer();
      _energyHistory.clear();
      _smoothedEnergy = 0;
      _baselineEnergy = 0;
      _visualEnergy = 0;
      _ticksSinceLastBeat = 0;
      _emit(AudioEnergyState(energy: 0, isPlaying: false));
    } else {
      _startTimer();
    }
  }

  Future<void> _loadWaveformForCurrentTrack() async {
    final token = ++_loadToken;
    final filename = await _resolveCurrentSongFilename();
    final path = await _resolveCurrentSongPath();
    if (token != _loadToken ||
        filename == null ||
        path == null ||
        path.isEmpty) {
      if (token == _loadToken) {
        _waveform = const [];
        _loadedFilename = filename;
      }
      return;
    }
    if (_loadedFilename == filename && _waveform.isNotEmpty) return;

    final samples = await _waveformService.getWaveform(filename, path);
    if (token != _loadToken) return;
    _waveform = samples;
    _loadedFilename = filename;
    _energyHistory.clear();
  }

  void _tick() {
    if (!_running) return;
    if (!_isAppActive || !_isPlaying) {
      if (_smoothedEnergy > 0.001) {
        _smoothedEnergy *= 0.70;
        _baselineEnergy *= 0.80;
        _visualEnergy *= 0.70;
        _emit(AudioEnergyState(
            energy: _visualEnergy.clamp(0.0, 1.0), isPlaying: _isPlaying));
      }
      return;
    }

    final duration = _player.duration;
    if (duration == null || duration == Duration.zero || _waveform.isEmpty) {
      _emit(AudioEnergyState(
          energy: _visualEnergy.clamp(0.0, 1.0), isPlaying: _isPlaying));
      return;
    }

    final sample = sampleEnergyAtPosition(
      waveform: _waveform,
      position: _player.position,
      duration: duration,
      windowRadius: 1,
    );

    final rawEnergy = sample * 64;

    _smoothedEnergy = _smoothedEnergy * 0.20 + rawEnergy * 0.80;
    _baselineEnergy = _baselineEnergy * 0.95 + rawEnergy * 0.05;

    final excess = (rawEnergy - _baselineEnergy).clamp(0.0, double.infinity);
    final strength = (excess / (_baselineEnergy + 0.01)).clamp(0.0, 2.0) / 2.0;

    if (strength > _visualEnergy) {
      _visualEnergy = strength;
    } else {
      _visualEnergy = _visualEnergy * 0.75 + strength * 0.25;
    }

    _ticksSinceLastBeat++;
    bool beatPulse = false;

    // 6 frames * 20ms = ~120ms rhythmic refractory period to prevent machine-gunning stutters
    if (_ticksSinceLastBeat >= 6) {
      beatPulse = detectBeatPulse(
        rawEnergy: rawEnergy,
        baseline: _baselineEnergy,
        history: _energyHistory,
        historySize: _historySize,
        beatMultiplier: _beatMultiplier,
      );
      if (beatPulse) {
        _ticksSinceLastBeat = 0;
      }
    } else {
      // Keep updating history even during cooldown window to prevent stale data spikes
      if (_energyHistory.length >= _historySize) _energyHistory.removeFirst();
      _energyHistory.add(rawEnergy);
    }

    _emit(
      AudioEnergyState(
        energy: _visualEnergy.clamp(0.0, 1.0),
        beatPulse: beatPulse,
        isPlaying: true,
      ),
    );
  }

  void _emit(AudioEnergyState state) {
    if (_controller.isClosed) return;
    _controller.add(state);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

@visibleForTesting
double sampleEnergyAtPosition({
  required List<double> waveform,
  required Duration position,
  required Duration duration,
  int windowRadius = 2,
}) {
  if (waveform.isEmpty || duration == Duration.zero) return 0;

  final progress =
      (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  final center =
      (progress * (waveform.length - 1)).round().clamp(0, waveform.length - 1);

  var sum = 0.0;
  var count = 0;
  for (var i = center - windowRadius; i <= center + windowRadius; i++) {
    if (i < 0 || i >= waveform.length) continue;
    sum += waveform[i];
    count++;
  }
  return count == 0 ? 0 : (sum / count).clamp(0.0, 1.0);
}

@visibleForTesting
bool detectBeatPulse({
  required double rawEnergy,
  required double baseline,
  required Queue<double> history,
  required int historySize,
  required double beatMultiplier,
}) {
  if (history.length >= historySize) {
    history.removeFirst();
  }
  history.add(rawEnergy);

  if (history.length < 3) return false;

  const double minEnergyFloor = 0.2;
  final localFloor = baseline * 0.25;
  return rawEnergy > baseline * beatMultiplier &&
      rawEnergy > max(localFloor, minEnergyFloor);
}

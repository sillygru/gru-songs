import 'dart:async';
import 'dart:collection';

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

  // Rapid sample rate (50Hz) ensures high-speed successive beats are never skipped
  static const Duration _sampleInterval = Duration(milliseconds: 20);
  static const int _historySize = 10;
  static const double _beatMultiplier = 1.05; // Lower ratio threshold to capture subtle accents

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
    _timer = Timer.periodic(_sampleInterval, (_) => _tick());
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _sequenceSub?.cancel();
    _sequenceSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _energyHistory.clear();
    _smoothedEnergy = 0;
    _baselineEnergy = 0;
    _visualEnergy = 0;
    _emit(const AudioEnergyState());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isActive = state == AppLifecycleState.resumed;
    if (_isAppActive == isActive) return;
    _isAppActive = isActive;
    if (!isActive) {
      _emit(const AudioEnergyState());
    }
  }

  void _onPlayerState(PlayerState state) {
    if (!_running) return;
    _isPlaying = state.playing;
    if (!state.playing) {
      _energyHistory.clear();
      _smoothedEnergy = 0;
      _baselineEnergy = 0;
      _visualEnergy = 0;
      _emit(AudioEnergyState(energy: 0, isPlaying: false));
    }
  }

  Future<void> _loadWaveformForCurrentTrack() async {
    final token = ++_loadToken;
    final filename = await _resolveCurrentSongFilename();
    final path = await _resolveCurrentSongPath();
    if (token != _loadToken || filename == null || path == null || path.isEmpty) {
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
        _emit(AudioEnergyState(energy: _visualEnergy.clamp(0.0, 1.0), isPlaying: _isPlaying));
      }
      return;
    }

    final duration = _player.duration;
    if (duration == null || duration == Duration.zero || _waveform.isEmpty) {
      _emit(AudioEnergyState(energy: _visualEnergy.clamp(0.0, 1.0), isPlaying: _isPlaying));
      return;
    }

    final sample = sampleEnergyAtPosition(
      waveform: _waveform,
      position: _player.position,
      duration: duration,
      windowRadius: 1, // Ultra tight single-frame tracking for snappy alignment
    );

    final rawEnergy = sample * 64;

    _smoothedEnergy = _smoothedEnergy * 0.20 + rawEnergy * 0.80;
    _baselineEnergy = _baselineEnergy * 0.96 + rawEnergy * 0.04;

    final excess = (rawEnergy - _baselineEnergy).clamp(0.0, double.infinity);
    final strength = (excess / (_baselineEnergy + 0.01)).clamp(0.0, 2.0) / 2.0;

    // Asymmetric Zero-Dampened Envelope: Instant spike on impact, snappy collapse
    if (strength > _visualEnergy) {
      _visualEnergy = strength; // 0% delay attack
    } else {
      _visualEnergy = _visualEnergy * 0.70 + strength * 0.30; // Quick decay to mirror real bass drop dynamics
    }

    final beatPulse = detectBeatPulse(
      rawEnergy: rawEnergy,
      baseline: _baselineEnergy,
      history: _energyHistory,
      historySize: _historySize,
      beatMultiplier: _beatMultiplier,
    );

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

  // Dynamic noise floor adapts instantly to quiet or loud sections
  final localFloor = baseline * 0.35;
  return rawEnergy > baseline * beatMultiplier && rawEnergy > localFloor;
}

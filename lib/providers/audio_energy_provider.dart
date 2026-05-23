import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_energy_analyzer.dart';

export '../services/audio_energy_analyzer.dart' show AudioEnergyState;
import 'providers.dart';
import 'settings_provider.dart';

final audioEnergyEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.beatReactiveCoverEnabled;
});

class PlayerScreenActiveNotifier extends Notifier<bool> {
  int _refCount = 0;

  @override
  bool build() => false;

  void setActive(bool active) {
    if (active) {
      _refCount++;
    } else if (_refCount > 0) {
      _refCount--;
    }
    state = _refCount > 0;
  }
}

final playerScreenActiveProvider =
    NotifierProvider<PlayerScreenActiveNotifier, bool>(
  PlayerScreenActiveNotifier.new,
);

final audioEnergyProvider =
    NotifierProvider<AudioEnergyNotifier, AudioEnergyState>(
  AudioEnergyNotifier.new,
);

class AudioEnergyNotifier extends Notifier<AudioEnergyState> {
  AudioEnergyAnalyzer? _analyzer;
  StreamSubscription<AudioEnergyState>? _subscription;

  @override
  AudioEnergyState build() {
    ref.listen<bool>(audioEnergyEnabledProvider, (_, __) => _sync());
    ref.listen<bool>(playerScreenActiveProvider, (_, __) => _sync());
    ref.onDispose(_disposeAnalyzer);
    _sync();
    return AudioEnergyState.idle;
  }

  void _sync() {
    final enabled = ref.read(audioEnergyEnabledProvider) &&
        ref.read(playerScreenActiveProvider);
    _syncAnalyzer(enabled);
  }

  void _syncAnalyzer(bool enabled) {
    if (!enabled) {
      _disposeAnalyzer();
      state = AudioEnergyState.idle;
      return;
    }

    if (_analyzer != null) return;

    final manager = ref.read(audioPlayerManagerProvider);
    _analyzer = AudioEnergyAnalyzer(
      player: manager.player,
      waveformService: ref.read(waveformServiceProvider),
      resolveCurrentSongFilename: () async {
        final song = manager.currentSongNotifier.value;
        return song?.filename;
      },
      resolveCurrentSongPath: () async {
        final song = manager.currentSongNotifier.value;
        return song?.url;
      },
    )..start();

    _subscription = _analyzer!.stream.listen((next) {
      state = next;
    });
  }

  void _disposeAnalyzer() {
    _subscription?.cancel();
    _subscription = null;
    _analyzer?.dispose();
    _analyzer = null;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool visualizerEnabled;

  SettingsState({
    this.visualizerEnabled = true,
  });

  SettingsState copyWith({
    bool? visualizerEnabled,
  }) {
    return SettingsState(
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _keyVisualizerEnabled = 'visualizer_enabled';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      visualizerEnabled: prefs.getBool(_keyVisualizerEnabled) ?? true,
    );
  }

  Future<void> setVisualizerEnabled(bool enabled) async {
    state = state.copyWith(visualizerEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVisualizerEnabled, enabled);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

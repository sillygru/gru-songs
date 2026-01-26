import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/telemetry_service.dart';

class SettingsState {
  final bool visualizerEnabled;
  final int telemetryLevel;

  SettingsState({
    this.visualizerEnabled = true,
    this.telemetryLevel = 1,
  });

  SettingsState copyWith({
    bool? visualizerEnabled,
    int? telemetryLevel,
  }) {
    return SettingsState(
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
      telemetryLevel: telemetryLevel ?? this.telemetryLevel,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _keyVisualizerEnabled = 'visualizer_enabled';
  static const _keyTelemetryLevel = 'telemetry_level';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      visualizerEnabled: prefs.getBool(_keyVisualizerEnabled) ?? true,
      telemetryLevel: prefs.getInt(_keyTelemetryLevel) ?? 1,
    );
  }

  Future<void> setVisualizerEnabled(bool enabled) async {
    state = state.copyWith(visualizerEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVisualizerEnabled, enabled);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'visualizer_enabled',
          'value': enabled,
        },
        requiredLevel: 2);
  }

  Future<void> setTelemetryLevel(int level) async {
    state = state.copyWith(telemetryLevel: level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTelemetryLevel, level);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'telemetry_level',
          'value': level,
        },
        requiredLevel: 2); // Changed to Level 2 per request
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

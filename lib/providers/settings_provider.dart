import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/telemetry_service.dart';

class SettingsState {
  final bool visualizerEnabled;
  final int telemetryLevel;
  final bool autoPauseOnVolumeZero;
  final bool autoResumeOnVolumeRestore;

  SettingsState({
    this.visualizerEnabled = true,
    this.telemetryLevel = 1,
    this.autoPauseOnVolumeZero = true,
    this.autoResumeOnVolumeRestore = true,
  });

  SettingsState copyWith({
    bool? visualizerEnabled,
    int? telemetryLevel,
    bool? autoPauseOnVolumeZero,
    bool? autoResumeOnVolumeRestore,
  }) {
    return SettingsState(
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
      telemetryLevel: telemetryLevel ?? this.telemetryLevel,
      autoPauseOnVolumeZero:
          autoPauseOnVolumeZero ?? this.autoPauseOnVolumeZero,
      autoResumeOnVolumeRestore:
          autoResumeOnVolumeRestore ?? this.autoResumeOnVolumeRestore,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _keyVisualizerEnabled = 'visualizer_enabled';
  static const _keyTelemetryLevel = 'telemetry_level';
  static const _keyAutoPauseOnVolumeZero = 'auto_pause_on_volume_zero';
  static const _keyAutoResumeOnVolumeRestore = 'auto_resume_on_volume_restore';

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
      autoPauseOnVolumeZero: prefs.getBool(_keyAutoPauseOnVolumeZero) ?? true,
      autoResumeOnVolumeRestore:
          prefs.getBool(_keyAutoResumeOnVolumeRestore) ?? true,
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

  Future<void> setAutoPauseOnVolumeZero(bool enabled) async {
    state = state.copyWith(autoPauseOnVolumeZero: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoPauseOnVolumeZero, enabled);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'auto_pause_on_volume_zero',
          'value': enabled,
        },
        requiredLevel: 2);
  }

  Future<void> setAutoResumeOnVolumeRestore(bool enabled) async {
    state = state.copyWith(autoResumeOnVolumeRestore: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoResumeOnVolumeRestore, enabled);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'auto_resume_on_volume_restore',
          'value': enabled,
        },
        requiredLevel: 2);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

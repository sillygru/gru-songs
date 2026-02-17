import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/quick_action_config.dart';
import '../services/telemetry_service.dart';

class SettingsState {
  final bool visualizerEnabled;
  final int telemetryLevel;
  final bool autoPauseOnVolumeZero;
  final bool autoResumeOnVolumeRestore;
  final SongSortOrder sortOrder;
  final bool showSongDuration;
  final bool animatedSoundWaveEnabled;
  final bool showWaveform;
  final double fadeOutDuration;
  final double fadeInDuration;
  final double delayDuration;
  final QuickActionConfig quickActionConfig;

  SettingsState({
    this.visualizerEnabled = true,
    this.telemetryLevel = 1,
    this.autoPauseOnVolumeZero = true,
    this.autoResumeOnVolumeRestore = true,
    this.sortOrder = SongSortOrder.title,
    this.showSongDuration = false,
    this.animatedSoundWaveEnabled = true,
    this.showWaveform = true,
    this.fadeOutDuration = 0.0,
    this.fadeInDuration = 0.0,
    this.delayDuration = 0.0,
    QuickActionConfig? quickActionConfig,
  }) : quickActionConfig = quickActionConfig ?? QuickActionConfig.defaults;

  SettingsState copyWith({
    bool? visualizerEnabled,
    int? telemetryLevel,
    bool? autoPauseOnVolumeZero,
    bool? autoResumeOnVolumeRestore,
    SongSortOrder? sortOrder,
    bool? showSongDuration,
    bool? animatedSoundWaveEnabled,
    bool? showWaveform,
    double? fadeOutDuration,
    double? fadeInDuration,
    double? delayDuration,
    QuickActionConfig? quickActionConfig,
  }) {
    return SettingsState(
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
      telemetryLevel: telemetryLevel ?? this.telemetryLevel,
      autoPauseOnVolumeZero:
          autoPauseOnVolumeZero ?? this.autoPauseOnVolumeZero,
      autoResumeOnVolumeRestore:
          autoResumeOnVolumeRestore ?? this.autoResumeOnVolumeRestore,
      sortOrder: sortOrder ?? this.sortOrder,
      showSongDuration: showSongDuration ?? this.showSongDuration,
      animatedSoundWaveEnabled:
          animatedSoundWaveEnabled ?? this.animatedSoundWaveEnabled,
      showWaveform: showWaveform ?? this.showWaveform,
      fadeOutDuration: fadeOutDuration ?? this.fadeOutDuration,
      fadeInDuration: fadeInDuration ?? this.fadeInDuration,
      delayDuration: delayDuration ?? this.delayDuration,
      quickActionConfig: quickActionConfig ?? this.quickActionConfig,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _keyVisualizerEnabled = 'visualizer_enabled';
  static const _keyTelemetryLevel = 'telemetry_level';
  static const _keyAutoPauseOnVolumeZero = 'auto_pause_on_volume_zero';
  static const _keyAutoResumeOnVolumeRestore = 'auto_resume_on_volume_restore';
  static const _keySortOrder = 'sort_order';
  static const _keyShowSongDuration = 'show_song_duration';
  static const _keyAnimatedSoundWaveEnabled = 'animated_sound_wave_enabled';
  static const _keyShowWaveform = 'show_waveform';
  static const _keyFadeOutDuration = 'fade_out_duration';
  static const _keyFadeInDuration = 'fade_in_duration';
  static const _keyDelayDuration = 'delay_duration';
  static const _keyQuickActionConfig = 'quick_action_config';
  static const double maxDelayDuration = 12.0;

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sortOrderIndex = prefs.getInt(_keySortOrder);
    state = SettingsState(
      visualizerEnabled: prefs.getBool(_keyVisualizerEnabled) ?? true,
      telemetryLevel: prefs.getInt(_keyTelemetryLevel) ?? 1,
      autoPauseOnVolumeZero: prefs.getBool(_keyAutoPauseOnVolumeZero) ?? true,
      autoResumeOnVolumeRestore:
          prefs.getBool(_keyAutoResumeOnVolumeRestore) ?? true,
      sortOrder: sortOrderIndex != null
          ? SongSortOrder.values[sortOrderIndex]
          : SongSortOrder.title,
      showSongDuration: prefs.getBool(_keyShowSongDuration) ?? false,
      animatedSoundWaveEnabled:
          prefs.getBool(_keyAnimatedSoundWaveEnabled) ?? true,
      showWaveform: prefs.getBool(_keyShowWaveform) ?? true,
      fadeOutDuration: prefs.getDouble(_keyFadeOutDuration) ?? 0.0,
      fadeInDuration: prefs.getDouble(_keyFadeInDuration) ?? 0.0,
      delayDuration: prefs.getDouble(_keyDelayDuration) ?? 0.0,
      quickActionConfig: QuickActionConfig.fromJsonString(
          prefs.getString(_keyQuickActionConfig) ?? ''),
    );
  }

  Future<void> setFadeOutDuration(double value) async {
    // If setting fade, disable gap
    if (value > 0) {
      await setDelayDuration(0.0);
    }
    state = state.copyWith(fadeOutDuration: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFadeOutDuration, value);
  }

  Future<void> setFadeInDuration(double value) async {
    // If setting fade, disable gap
    if (value > 0) {
      await setDelayDuration(0.0);
    }
    state = state.copyWith(fadeInDuration: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFadeInDuration, value);
  }

  Future<void> setDelayDuration(double value) async {
    final clampedValue = value.clamp(0.0, maxDelayDuration);

    // If setting gap, disable fade
    if (clampedValue > 0) {
      await _disableFadeWithoutNotification();
    }

    state = state.copyWith(delayDuration: clampedValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDelayDuration, clampedValue);
  }

  Future<void> _disableFadeWithoutNotification() async {
    state = state.copyWith(fadeOutDuration: 0.0, fadeInDuration: 0.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFadeOutDuration, 0.0);
    await prefs.setDouble(_keyFadeInDuration, 0.0);
  }

  Future<void> setShowSongDuration(bool show) async {
    state = state.copyWith(showSongDuration: show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowSongDuration, show);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'show_song_duration',
          'value': show,
        },
        requiredLevel: 2);
  }

  Future<void> setSortOrder(SongSortOrder order) async {
    state = state.copyWith(sortOrder: order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySortOrder, order.index);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'sort_order',
          'value': order.name,
        },
        requiredLevel: 2);
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
        requiredLevel: 2);
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

  Future<void> setAnimatedSoundWaveEnabled(bool enabled) async {
    state = state.copyWith(animatedSoundWaveEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimatedSoundWaveEnabled, enabled);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'animated_sound_wave_enabled',
          'value': enabled,
        },
        requiredLevel: 2);
  }

  Future<void> setShowWaveform(bool enabled) async {
    state = state.copyWith(showWaveform: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowWaveform, enabled);

    await TelemetryService.instance.trackEvent(
        'setting_changed',
        {
          'setting': 'show_waveform',
          'value': enabled,
        },
        requiredLevel: 2);
  }

  Future<void> setQuickActionConfig(QuickActionConfig config) async {
    state = state.copyWith(quickActionConfig: config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuickActionConfig, config.toJsonString());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

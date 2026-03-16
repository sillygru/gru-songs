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
  final int autoBackupFrequencyHours;
  final int autoBackupDeleteAfterDays;
  final bool preventDuplicateTracks;
  final bool extractFeatArtists;
  final int minimumFileSizeBytes;
  final int minimumTrackDurationMs;
  final bool includeVideos;
  final double playFadeDuration;
  final double pauseFadeDuration;
  final bool keepScreenAwakeOnLyrics;
  final PlayerCoverSizingMode coverSizingMode;

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
    this.autoBackupFrequencyHours = 0,
    this.autoBackupDeleteAfterDays = 0,
    this.preventDuplicateTracks = true,
    this.extractFeatArtists = false,
    this.minimumFileSizeBytes = 102400,
    this.minimumTrackDurationMs = 10000,
    this.includeVideos = true,
    this.playFadeDuration = 0.3,
    this.pauseFadeDuration = 0.3,
    this.keepScreenAwakeOnLyrics = true,
    this.coverSizingMode = PlayerCoverSizingMode.autoFit,
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
    int? autoBackupFrequencyHours,
    int? autoBackupDeleteAfterDays,
    bool? preventDuplicateTracks,
    bool? extractFeatArtists,
    int? minimumFileSizeBytes,
    int? minimumTrackDurationMs,
    bool? includeVideos,
    double? playFadeDuration,
    double? pauseFadeDuration,
    bool? keepScreenAwakeOnLyrics,
    PlayerCoverSizingMode? coverSizingMode,
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
      autoBackupFrequencyHours:
          autoBackupFrequencyHours ?? this.autoBackupFrequencyHours,
      autoBackupDeleteAfterDays:
          autoBackupDeleteAfterDays ?? this.autoBackupDeleteAfterDays,
      preventDuplicateTracks:
          preventDuplicateTracks ?? this.preventDuplicateTracks,
      extractFeatArtists: extractFeatArtists ?? this.extractFeatArtists,
      minimumFileSizeBytes: minimumFileSizeBytes ?? this.minimumFileSizeBytes,
      minimumTrackDurationMs:
          minimumTrackDurationMs ?? this.minimumTrackDurationMs,
      includeVideos: includeVideos ?? this.includeVideos,
      playFadeDuration: playFadeDuration ?? this.playFadeDuration,
      pauseFadeDuration: pauseFadeDuration ?? this.pauseFadeDuration,
      keepScreenAwakeOnLyrics:
          keepScreenAwakeOnLyrics ?? this.keepScreenAwakeOnLyrics,
      coverSizingMode: coverSizingMode ?? this.coverSizingMode,
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
  static const _keyAutoBackupFrequencyHours = 'auto_backup_frequency_hours';
  static const _keyAutoBackupDeleteAfterDays = 'auto_backup_delete_after_days';
  static const _keyPreventDuplicateTracks = 'prevent_duplicate_tracks';
  static const _keyExtractFeatArtists = 'extract_feat_artists';
  static const _keyMinimumFileSizeBytes = 'minimum_file_size_bytes';
  static const _keyMinimumTrackDurationMs = 'minimum_track_duration_ms';
  static const _keyIncludeVideos = 'include_videos';
  static const _keyPlayFadeDuration = 'play_fade_duration';
  static const _keyPauseFadeDuration = 'pause_fade_duration';
  static const _keyKeepScreenAwakeOnLyrics = 'keep_screen_awake_on_lyrics';
  static const _keyCoverSizingMode = 'cover_sizing_mode';
  static const double maxDelayDuration = 12.0;

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sortOrderIndex = prefs.getInt(_keySortOrder);
    final coverSizingModeIndex = prefs.getInt(_keyCoverSizingMode);
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
      autoBackupFrequencyHours: prefs.getInt(_keyAutoBackupFrequencyHours) ?? 0,
      autoBackupDeleteAfterDays:
          prefs.getInt(_keyAutoBackupDeleteAfterDays) ?? 0,
      preventDuplicateTracks: prefs.getBool(_keyPreventDuplicateTracks) ?? true,
      extractFeatArtists: prefs.getBool(_keyExtractFeatArtists) ?? false,
      minimumFileSizeBytes: prefs.getInt(_keyMinimumFileSizeBytes) ?? 102400,
      minimumTrackDurationMs: prefs.getInt(_keyMinimumTrackDurationMs) ?? 10000,
      includeVideos: prefs.getBool(_keyIncludeVideos) ?? true,
      playFadeDuration: prefs.getDouble(_keyPlayFadeDuration) ?? 0.3,
      pauseFadeDuration: prefs.getDouble(_keyPauseFadeDuration) ?? 0.3,
      keepScreenAwakeOnLyrics:
          prefs.getBool(_keyKeepScreenAwakeOnLyrics) ?? true,
      coverSizingMode: coverSizingModeIndex != null &&
              coverSizingModeIndex >= 0 &&
              coverSizingModeIndex < PlayerCoverSizingMode.values.length
          ? PlayerCoverSizingMode.values[coverSizingModeIndex]
          : PlayerCoverSizingMode.autoFit,
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

  Future<void> setAutoBackupFrequencyHours(int hours) async {
    state = state.copyWith(autoBackupFrequencyHours: hours);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoBackupFrequencyHours, hours);
  }

  Future<void> setAutoBackupDeleteAfterDays(int days) async {
    state = state.copyWith(autoBackupDeleteAfterDays: days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoBackupDeleteAfterDays, days);
  }

  Future<void> setPreventDuplicateTracks(bool enabled) async {
    state = state.copyWith(preventDuplicateTracks: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPreventDuplicateTracks, enabled);
  }

  Future<void> setExtractFeatArtists(bool enabled) async {
    state = state.copyWith(extractFeatArtists: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyExtractFeatArtists, enabled);
  }

  Future<void> setMinimumFileSizeBytes(int bytes) async {
    state = state.copyWith(minimumFileSizeBytes: bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinimumFileSizeBytes, bytes);
  }

  Future<void> setMinimumTrackDurationMs(int ms) async {
    state = state.copyWith(minimumTrackDurationMs: ms);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinimumTrackDurationMs, ms);
  }

  Future<void> setIncludeVideos(bool enabled) async {
    state = state.copyWith(includeVideos: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIncludeVideos, enabled);
  }

  Future<void> setPlayFadeDuration(double value) async {
    state = state.copyWith(playFadeDuration: value.clamp(0.0, 1.0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPlayFadeDuration, value.clamp(0.0, 1.0));
  }

  Future<void> setPauseFadeDuration(double value) async {
    state = state.copyWith(pauseFadeDuration: value.clamp(0.0, 1.0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPauseFadeDuration, value.clamp(0.0, 1.0));
  }

  Future<void> setKeepScreenAwakeOnLyrics(bool enabled) async {
    state = state.copyWith(keepScreenAwakeOnLyrics: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepScreenAwakeOnLyrics, enabled);
  }

  Future<void> setCoverSizingMode(PlayerCoverSizingMode mode) async {
    state = state.copyWith(coverSizingMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoverSizingMode, mode.index);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

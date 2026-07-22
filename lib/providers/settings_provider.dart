import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/quick_action_config.dart';
import '../services/telemetry_service.dart';

class SettingsState {
  final bool visualizerEnabled;
  final bool autoHideBottomBarOnScroll;
  final bool telemetryEnabled;
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
  final bool preventMergedDuplicates;
  final bool extractFeatArtists;
  final int minimumFileSizeBytes;
  final int minimumTrackDurationMs;
  final bool includeVideos;
  final double playFadeDuration;
  final double pauseFadeDuration;
  final bool keepScreenAwakeOnLyrics;
  final PlayerCoverSizingMode coverSizingMode;
  final bool lyricsBlurOverlayEnabled;
  final bool beatReactiveCoverEnabled;
  final bool beatReactiveParticlesEnabled;
  final PlayerMotionIntensity playerMotionIntensity;
  final int playerMotionLatencyMs;
  final bool showProgressiveBlurHeaders;
  final bool showQuickPicks;
  final bool showRecentQueues;
  final bool showForYou;

  SettingsState({
    this.visualizerEnabled = true,
    this.autoHideBottomBarOnScroll = true,
    this.telemetryEnabled = true,
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
    this.preventMergedDuplicates = true,
    this.extractFeatArtists = false,
    this.minimumFileSizeBytes = 102400,
    this.minimumTrackDurationMs = 10000,
    this.includeVideos = true,
    this.playFadeDuration = 0.3,
    this.pauseFadeDuration = 0.3,
    this.keepScreenAwakeOnLyrics = true,
    this.coverSizingMode = PlayerCoverSizingMode.autoFit,
    this.lyricsBlurOverlayEnabled = true,
    this.beatReactiveCoverEnabled = true,
    this.beatReactiveParticlesEnabled = true,
    this.playerMotionIntensity = PlayerMotionIntensity.subtle,
    this.playerMotionLatencyMs = 80,
    this.showProgressiveBlurHeaders = false,
    this.showQuickPicks = true,
    this.showRecentQueues = true,
    this.showForYou = true,
  }) : quickActionConfig = quickActionConfig ?? QuickActionConfig.defaults;

  SettingsState copyWith({
    bool? visualizerEnabled,
    bool? autoHideBottomBarOnScroll,
    bool? telemetryEnabled,
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
    bool? preventMergedDuplicates,
    bool? extractFeatArtists,
    int? minimumFileSizeBytes,
    int? minimumTrackDurationMs,
    bool? includeVideos,
    double? playFadeDuration,
    double? pauseFadeDuration,
    bool? keepScreenAwakeOnLyrics,
    PlayerCoverSizingMode? coverSizingMode,
    bool? lyricsBlurOverlayEnabled,
    bool? beatReactiveCoverEnabled,
    bool? beatReactiveParticlesEnabled,
    PlayerMotionIntensity? playerMotionIntensity,
    int? playerMotionLatencyMs,
    bool? showProgressiveBlurHeaders,
    bool? showQuickPicks,
    bool? showRecentQueues,
    bool? showForYou,
  }) {
    return SettingsState(
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
      autoHideBottomBarOnScroll:
          autoHideBottomBarOnScroll ?? this.autoHideBottomBarOnScroll,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
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
      preventMergedDuplicates:
          preventMergedDuplicates ?? this.preventMergedDuplicates,
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
      lyricsBlurOverlayEnabled:
          lyricsBlurOverlayEnabled ?? this.lyricsBlurOverlayEnabled,
      beatReactiveCoverEnabled:
          beatReactiveCoverEnabled ?? this.beatReactiveCoverEnabled,
      beatReactiveParticlesEnabled:
          beatReactiveParticlesEnabled ?? this.beatReactiveParticlesEnabled,
      playerMotionIntensity:
          playerMotionIntensity ?? this.playerMotionIntensity,
      playerMotionLatencyMs:
          playerMotionLatencyMs ?? this.playerMotionLatencyMs,
      showProgressiveBlurHeaders:
          showProgressiveBlurHeaders ?? this.showProgressiveBlurHeaders,
      showQuickPicks: showQuickPicks ?? this.showQuickPicks,
      showRecentQueues: showRecentQueues ?? this.showRecentQueues,
      showForYou: showForYou ?? this.showForYou,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _keyVisualizerEnabled = 'visualizer_enabled';
  static const _keyAutoHideBottomBarOnScroll = 'auto_hide_bottom_bar_on_scroll';
  static const _keyTelemetryEnabled = 'telemetry_enabled';
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
  static const _keyPreventMergedDuplicates = 'prevent_merged_duplicates';
  static const _keyExtractFeatArtists = 'extract_feat_artists';
  static const _keyMinimumFileSizeBytes = 'minimum_file_size_bytes';
  static const _keyMinimumTrackDurationMs = 'minimum_track_duration_ms';
  static const _keyIncludeVideos = 'include_videos';
  static const _keyPlayFadeDuration = 'play_fade_duration';
  static const _keyPauseFadeDuration = 'pause_fade_duration';
  static const _keyKeepScreenAwakeOnLyrics = 'keep_screen_awake_on_lyrics';
  static const _keyCoverSizingMode = 'cover_sizing_mode';
  static const _keyLyricsBlurOverlayEnabled = 'lyrics_blur_overlay_enabled';
  static const _keyBeatReactiveCoverEnabled = 'beat_reactive_cover_enabled';
  static const _keyBeatReactiveParticlesEnabled =
      'beat_reactive_particles_enabled';
  static const _keyPlayerMotionIntensity = 'player_motion_intensity';
  static const _keyPlayerMotionLatencyMs = 'player_motion_latency_ms';
  static const _keyProgressiveBlurHeaders = 'progressive_blur_headers';
  static const _keyShowQuickPicks = 'show_quick_picks';
  static const _keyShowRecentQueues = 'show_recent_queues';
  static const _keyShowForYou = 'show_for_you';
  static const double maxDelayDuration = 12.0;
  static const int minMotionLatencyMs = -200;
  static const int maxMotionLatencyMs = 500;

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sortOrderIndex = prefs.getInt(_keySortOrder);
    final coverSizingModeIndex = prefs.getInt(_keyCoverSizingMode);
    final motionIntensityIndex = prefs.getInt(_keyPlayerMotionIntensity);
    state = SettingsState(
      visualizerEnabled: prefs.getBool(_keyVisualizerEnabled) ?? true,
      autoHideBottomBarOnScroll:
          prefs.getBool(_keyAutoHideBottomBarOnScroll) ?? true,
      telemetryEnabled: prefs.getBool(_keyTelemetryEnabled) ?? true,
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
      preventMergedDuplicates:
          prefs.getBool(_keyPreventMergedDuplicates) ?? true,
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
      lyricsBlurOverlayEnabled:
          prefs.getBool(_keyLyricsBlurOverlayEnabled) ?? true,
      beatReactiveCoverEnabled:
          prefs.getBool(_keyBeatReactiveCoverEnabled) ?? true,
      beatReactiveParticlesEnabled:
          prefs.getBool(_keyBeatReactiveParticlesEnabled) ?? true,
      playerMotionIntensity: motionIntensityIndex != null &&
              motionIntensityIndex >= 0 &&
              motionIntensityIndex < PlayerMotionIntensity.values.length
          ? PlayerMotionIntensity.values[motionIntensityIndex]
          : PlayerMotionIntensity.subtle,
      playerMotionLatencyMs:
          (prefs.getInt(_keyPlayerMotionLatencyMs) ?? 80).clamp(-200, 500),
      showProgressiveBlurHeaders:
          prefs.getBool(_keyProgressiveBlurHeaders) ?? false,
      showQuickPicks: prefs.getBool(_keyShowQuickPicks) ?? true,
      showRecentQueues: prefs.getBool(_keyShowRecentQueues) ?? true,
      showForYou: prefs.getBool(_keyShowForYou) ?? true,
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
  }

  Future<void> setSortOrder(SongSortOrder order) async {
    state = state.copyWith(sortOrder: order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySortOrder, order.index);
  }

  Future<void> setVisualizerEnabled(bool enabled) async {
    state = state.copyWith(visualizerEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVisualizerEnabled, enabled);
  }

  Future<void> setAutoHideBottomBarOnScroll(bool enabled) async {
    state = state.copyWith(autoHideBottomBarOnScroll: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoHideBottomBarOnScroll, enabled);
  }

  Future<void> setTelemetryEnabled(bool enabled) async {
    state = state.copyWith(telemetryEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTelemetryEnabled, enabled);

    TelemetryService.instance.reportTelemetryToggle(enabled);
  }

  Future<void> setAutoPauseOnVolumeZero(bool enabled) async {
    state = state.copyWith(autoPauseOnVolumeZero: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoPauseOnVolumeZero, enabled);
  }

  Future<void> setAutoResumeOnVolumeRestore(bool enabled) async {
    state = state.copyWith(autoResumeOnVolumeRestore: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoResumeOnVolumeRestore, enabled);
  }

  Future<void> setAnimatedSoundWaveEnabled(bool enabled) async {
    state = state.copyWith(animatedSoundWaveEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimatedSoundWaveEnabled, enabled);
  }

  Future<void> setShowWaveform(bool enabled) async {
    state = state.copyWith(showWaveform: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowWaveform, enabled);
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

  Future<void> setPreventMergedDuplicates(bool enabled) async {
    state = state.copyWith(preventMergedDuplicates: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPreventMergedDuplicates, enabled);
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

  Future<void> setLyricsBlurOverlayEnabled(bool enabled) async {
    state = state.copyWith(lyricsBlurOverlayEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLyricsBlurOverlayEnabled, enabled);
  }

  Future<void> setBeatReactiveCoverEnabled(bool enabled) async {
    state = state.copyWith(beatReactiveCoverEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBeatReactiveCoverEnabled, enabled);
  }

  Future<void> setBeatReactiveParticlesEnabled(bool enabled) async {
    state = state.copyWith(beatReactiveParticlesEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBeatReactiveParticlesEnabled, enabled);
  }

  Future<void> setPlayerMotionIntensity(PlayerMotionIntensity value) async {
    state = state.copyWith(playerMotionIntensity: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPlayerMotionIntensity, value.index);
  }

  /// Visual offset compensating audio output latency, in milliseconds.
  /// Bluetooth commonly needs 150-250ms where wired needs almost none, so this
  /// has to be adjustable rather than a build-time constant.
  Future<void> setPlayerMotionLatencyMs(int value) async {
    final clamped = value.clamp(minMotionLatencyMs, maxMotionLatencyMs);
    state = state.copyWith(playerMotionLatencyMs: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPlayerMotionLatencyMs, clamped);
  }

  Future<void> setProgressiveBlurHeaders(bool enabled) async {
    state = state.copyWith(showProgressiveBlurHeaders: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProgressiveBlurHeaders, enabled);
  }

  Future<void> setShowQuickPicks(bool show) async {
    state = state.copyWith(showQuickPicks: show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowQuickPicks, show);
  }

  Future<void> setShowRecentQueues(bool show) async {
    state = state.copyWith(showRecentQueues: show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowRecentQueues, show);
  }

  Future<void> setShowForYou(bool show) async {
    state = state.copyWith(showForYou: show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowForYou, show);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

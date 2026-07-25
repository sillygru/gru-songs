import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../tokens/app_icons.dart';

class PlaybackSettingsScreen extends ConsumerStatefulWidget {
  /// Row to reveal when opened from settings search.
  final String? highlightId;

  const PlaybackSettingsScreen({super.key, this.highlightId});

  @override
  ConsumerState<PlaybackSettingsScreen> createState() =>
      _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState
    extends ConsumerState<PlaybackSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    // Gap and fade are mutually exclusive; whichever is non-zero disables the
    // other's sliders.
    final bool isGapMode = settings.delayDuration > 0;
    final bool isFadeMode =
        settings.fadeOutDuration > 0 || settings.fadeInDuration > 0;

    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Playback'),
      body: AppSettingsList(
        highlightId: widget.highlightId,
        children: [
          AppSettingsGroup(
            label: 'Audio',
            icon: AppIcons.playCircle,
            children: [
              AppSettingsSwitch(
                icon: AppIcons.volumeOff,
                searchId: 'playback.auto_pause_mute',
                title: 'Auto-Pause on Mute',
                subtitle: 'Pause playback when volume reaches 0',
                value: settings.autoPauseOnVolumeZero,
                onChanged: notifier.setAutoPauseOnVolumeZero,
              ),
              AppSettingsSwitch(
                icon: AppIcons.volumeUp,
                searchId: 'playback.auto_resume_unmute',
                title: 'Auto-Resume on Unmute',
                subtitle: 'Resume playback when volume is restored',
                value: settings.autoResumeOnVolumeRestore,
                onChanged: notifier.setAutoResumeOnVolumeRestore,
              ),
              AppSettingsSwitch(
                icon: AppIcons.screenLock,
                searchId: 'playback.keep_screen_awake',
                title: 'Keep Screen Awake on Lyrics',
                subtitle: 'Prevent sleep while the lyrics pane is open',
                value: settings.keepScreenAwakeOnLyrics,
                onChanged: notifier.setKeepScreenAwakeOnLyrics,
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Transitions',
            icon: AppIcons.swapHoriz,
            children: [
              AppSettingsSlider(
                icon: AppIcons.hourglass,
                searchId: 'playback.gap',
                title: isFadeMode ? 'Gap / Delay (off)' : 'Gap / Delay',
                valueLabel: '${settings.delayDuration.toStringAsFixed(1)}s',
                value: settings.delayDuration,
                min: 0,
                max: 12,
                divisions: 24,
                onChanged: isFadeMode ? (_) {} : notifier.setDelayDuration,
              ),
              AppSettingsSlider(
                icon: AppIcons.volumeDown,
                searchId: 'playback.fade_out',
                title: isGapMode ? 'Fade Out (off)' : 'Fade Out',
                valueLabel: '${settings.fadeOutDuration.toStringAsFixed(1)}s',
                value: settings.fadeOutDuration,
                min: 0,
                max: 12,
                divisions: 24,
                onChanged: isGapMode ? (_) {} : notifier.setFadeOutDuration,
              ),
              AppSettingsSlider(
                icon: AppIcons.volumeUp,
                searchId: 'playback.fade_in',
                title: isGapMode ? 'Fade In (off)' : 'Fade In',
                valueLabel: '${settings.fadeInDuration.toStringAsFixed(1)}s',
                value: settings.fadeInDuration,
                min: 0,
                max: 12,
                divisions: 24,
                onChanged: isGapMode ? (_) {} : notifier.setFadeInDuration,
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Play / Pause',
            icon: AppIcons.playCircle,
            children: [
              AppSettingsSlider(
                icon: AppIcons.play,
                searchId: 'playback.fade_play',
                title: 'Fade on Play',
                valueLabel: _fadeLabel(settings.playFadeDuration),
                value: settings.playFadeDuration,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: notifier.setPlayFadeDuration,
              ),
              AppSettingsSlider(
                icon: AppIcons.pause,
                searchId: 'playback.fade_pause',
                title: 'Fade on Pause',
                valueLabel: _fadeLabel(settings.pauseFadeDuration),
                value: settings.pauseFadeDuration,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: notifier.setPauseFadeDuration,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fadeLabel(double value) {
    if (value == 0) return 'Off';
    if (value >= 1.0) return '1.0 s';
    return '${(value * 1000).round()} ms';
  }
}

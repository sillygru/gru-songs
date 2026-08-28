import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../dialogs/lyrics_translation_sheet.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';

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
            label: 'Lyrics',
            icon: AppIcons.subtitles,
            children: [
              AppSettingsSwitch(
                icon: AppIcons.autoAwesome,
                searchId: 'playback.lyrics_rich_sync',
                title: 'Simulate Word Sync',
                subtitle:
                    'Generate word-level timing from line-synced lyrics using prosodic estimation',
                value: settings.lyricsSimulatedRichSyncEnabled,
                onChanged: notifier.setLyricsSimulatedRichSyncEnabled,
              ),
              AppSettingsSwitch(
                icon: AppIcons.screenLock,
                searchId: 'playback.keep_screen_awake',
                title: 'Keep Screen Awake on Lyrics',
                subtitle: 'Prevent sleep while the lyrics pane is open',
                value: settings.keepScreenAwakeOnLyrics,
                onChanged: notifier.setKeepScreenAwakeOnLyrics,
              ),
              AppSettingsSwitch(
                icon: AppIcons.translate,
                searchId: 'playback.lyrics_auto_translate',
                title: 'Auto-Translate Lyrics',
                subtitle:
                    'Automatically translate lyrics using selected target language',
                value: settings.lyricsAutoTranslate,
                onChanged: notifier.setLyricsAutoTranslate,
              ),
              AppSettingsAnchor(
                id: 'playback.lyrics_target_lang',
                child: AppListRow(
                  dense: true,
                  leading: AppRowIcon(
                    icon: AppIcons.translate,
                    color: AppTokens.accentOf(context, ref),
                    size: 40,
                  ),
                  title: 'Target Language',
                  subtitle: kSupportedTranslationLanguages[
                          settings.lyricsTargetLanguage] ??
                      settings.lyricsTargetLanguage.toUpperCase(),
                  trailing: DropdownButton<String>(
                    value: kSupportedTranslationLanguages
                            .containsKey(settings.lyricsTargetLanguage)
                        ? settings.lyricsTargetLanguage
                        : 'es',
                    underline: const SizedBox.shrink(),
                    borderRadius: AppTokens.brMd,
                    items: kSupportedTranslationLanguages.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) notifier.setLyricsTargetLanguage(val);
                    },
                  ),
                ),
              ),
              AppSettingsAnchor(
                id: 'playback.lyrics_translation_mode',
                child: AppListRow(
                  dense: true,
                  leading: AppRowIcon(
                    icon: AppIcons.subtitles,
                    color: AppTokens.accentOf(context, ref),
                    size: 40,
                  ),
                  title: 'Translation Display',
                  subtitle: settings.lyricsTranslationMode == 'replace'
                      ? 'Replace base lyrics'
                      : 'Show subtext below lyrics',
                  trailing: DropdownButton<String>(
                    value: settings.lyricsTranslationMode,
                    underline: const SizedBox.shrink(),
                    borderRadius: AppTokens.brMd,
                    items: const [
                      DropdownMenuItem(
                        value: 'subtext',
                        child: Text('Subtext below'),
                      ),
                      DropdownMenuItem(
                        value: 'replace',
                        child: Text('Replace base'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.setLyricsTranslationMode(val);
                    },
                  ),
                ),
              ),
            ],
          ),
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

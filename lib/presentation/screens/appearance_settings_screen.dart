import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/settings_provider.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_tokens.dart';
import 'quick_actions_settings_screen.dart';
import '../tokens/app_icons.dart';

class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  /// Row to reveal when opened from settings search.
  final String? highlightId;

  const AppearanceSettingsScreen({super.key, this.highlightId});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState
    extends ConsumerState<AppearanceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final accent = AppTokens.accentOf(context, ref);

    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Appearance'),
      body: AppSettingsList(
        highlightId: widget.highlightId,
        children: [
          AppSettingsGroup(
            label: 'Display',
            icon: AppIcons.viewList,
            children: [
              AppSettingsAnchor(
                id: 'appearance.visualizer',
                child: AppListRow(
                  dense: true,
                  leading: AppRowIcon(
                    icon: AppIcons.waves,
                    color: accent,
                    size: 40,
                  ),
                  title: 'Audio Visualizer',
                  subtitle: 'Bars over the artwork while playing — synced '
                      'follows the song, bass on the left',
                  trailing: DropdownButton<VisualizerMode>(
                    value: settings.visualizerMode,
                    underline: const SizedBox.shrink(),
                    borderRadius: AppTokens.brMd,
                    onChanged: (value) {
                      if (value == null) return;
                      notifier.setVisualizerMode(value);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: VisualizerMode.off,
                        child: Text('Off'),
                      ),
                      DropdownMenuItem(
                        value: VisualizerMode.classic,
                        child: Text('Classic'),
                      ),
                      DropdownMenuItem(
                        value: VisualizerMode.synced,
                        child: Text('Synced'),
                      ),
                    ],
                  ),
                ),
              ),
              AppSettingsSwitch(
                icon: AppIcons.graphicEq,
                searchId: 'appearance.waveform',
                title: 'Waveform Progress Bar',
                subtitle: 'Show song waveform in player',
                value: settings.showWaveform,
                onChanged: notifier.setShowWaveform,
              ),
              AppSettingsSwitch(
                icon: AppIcons.touchApp,
                searchId: 'appearance.waveform_haptics',
                title: 'Waveform Scrubbing Haptics',
                subtitle: 'Haptic feedback for each bar while seeking',
                value: settings.waveformHapticsEnabled,
                onChanged: notifier.setWaveformHapticsEnabled,
              ),
              AppSettingsSwitch(
                icon: AppIcons.timer,
                searchId: 'appearance.song_duration',
                title: 'Show Song Duration',
                subtitle: 'Display duration in song lists',
                value: settings.showSongDuration,
                onChanged: notifier.setShowSongDuration,
              ),
              AppSettingsSwitch(
                icon: AppIcons.swapVert,
                searchId: 'appearance.auto_hide_bars',
                title: 'Auto-Hide Bars',
                subtitle:
                    'Header and bottom dock hide on downward scroll, restore on upward scroll',
                value: settings.autoHideBottomBarOnScroll,
                onChanged: notifier.setAutoHideBottomBarOnScroll,
              ),
              AppSettingsSwitch(
                icon: AppIcons.blur,
                searchId: 'appearance.lyrics_blur',
                title: 'Lyrics blur overlay',
                subtitle: 'Progressive blur on the lyrics',
                value: settings.lyricsBlurOverlayEnabled,
                onChanged: notifier.setLyricsBlurOverlayEnabled,
              ),
              AppSettingsAnchor(
                id: 'appearance.cover_sizing',
                child: AppListRow(
                  dense: true,
                  leading: AppRowIcon(
                    icon: AppIcons.photoSize,
                    color: accent,
                    size: 40,
                  ),
                  title: 'Player Cover Sizing',
                  subtitle: 'Auto-fit or preserve source aspect ratio',
                  trailing: DropdownButton<PlayerCoverSizingMode>(
                    value: settings.coverSizingMode,
                    underline: const SizedBox.shrink(),
                    borderRadius: AppTokens.brMd,
                    onChanged: (value) {
                      if (value == null) return;
                      notifier.setCoverSizingMode(value);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: PlayerCoverSizingMode.autoFit,
                        child: Text('Auto Fit'),
                      ),
                      DropdownMenuItem(
                        value: PlayerCoverSizingMode.sourceAspect,
                        child: Text('Source Size'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Player motion',
            icon: AppIcons.graphicEq,
            children: [
              AppSettingsSwitch(
                icon: AppIcons.album,
                searchId: 'appearance.beat_cover',
                title: 'Beat-reactive cover',
                subtitle: 'Album art pulses with the beat',
                value: settings.beatReactiveCoverEnabled,
                onChanged: notifier.setBeatReactiveCoverEnabled,
              ),
              // Cover intensity — only visible when the cover toggle is on.
              if (settings.beatReactiveCoverEnabled)
                _MotionIntensityRow(
                  id: 'appearance.cover_intensity',
                  accent: accent,
                  title: 'Cover intensity',
                  subtitle: 'How strongly the cover reacts',
                  intensity: settings.coverMotionIntensity,
                  customIntensity: settings.coverMotionCustomIntensity,
                  onIntensityChanged: notifier.setCoverMotionIntensity,
                  onCustomChanged: notifier.setCoverMotionCustomIntensity,
                ),
              AppSettingsSwitch(
                icon: AppIcons.autoAwesome,
                searchId: 'appearance.beat_particles',
                title: 'Beat-reactive particles',
                subtitle: 'Floating particles that drift and breathe with the '
                    'music',
                value: settings.beatReactiveParticlesEnabled,
                onChanged: notifier.setBeatReactiveParticlesEnabled,
              ),
              // Particle intensity — only visible when the particle toggle is on.
              if (settings.beatReactiveParticlesEnabled)
                _MotionIntensityRow(
                  id: 'appearance.particle_intensity',
                  accent: accent,
                  title: 'Particle density',
                  subtitle: 'How many particles and how lively',
                  intensity: settings.particleMotionIntensity,
                  customIntensity: settings.particleMotionCustomIntensity,
                  onIntensityChanged: notifier.setParticleMotionIntensity,
                  onCustomChanged: notifier.setParticleMotionCustomIntensity,
                ),
              // Output latency is a property of the listener's hardware, not the
              // app: Bluetooth typically runs 150-250ms behind wired. Without
              // this the pulse is permanently early on BT with no recourse.
              AppSettingsAnchor(
                id: 'appearance.beat_offset',
                child: AppListRow(
                  dense: true,
                  leading: AppRowIcon(
                    icon: AppIcons.syncAlt,
                    color: accent,
                    size: 40,
                  ),
                  title: 'Beat sync offset',
                  subtitle: settings.playerMotionLatencyMs == 0
                      ? 'No offset — raise it if the pulse feels early'
                      : '${settings.playerMotionLatencyMs} ms '
                          '(raise for Bluetooth)',
                  trailing: SizedBox(
                    width: 160,
                    child: Slider(
                      value: settings.playerMotionLatencyMs.toDouble(),
                      min: SettingsNotifier.minMotionLatencyMs.toDouble(),
                      max: SettingsNotifier.maxMotionLatencyMs.toDouble(),
                      divisions: (SettingsNotifier.maxMotionLatencyMs -
                              SettingsNotifier.minMotionLatencyMs) ~/
                          10,
                      label: '${settings.playerMotionLatencyMs} ms',
                      onChanged: (value) =>
                          notifier.setPlayerMotionLatencyMs(value.round()),
                    ),
                  ),
                ),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Home screen',
            icon: AppIcons.home,
            children: [
              AppSettingsSwitch(
                icon: AppIcons.autoAwesome,
                searchId: 'appearance.quick_picks',
                title: 'Quick Picks',
                subtitle: 'Show quick pick recommendations',
                value: settings.showQuickPicks,
                onChanged: notifier.setShowQuickPicks,
              ),
              AppSettingsSwitch(
                icon: AppIcons.clock,
                searchId: 'appearance.recent_queues',
                title: 'Recent Queues',
                subtitle: 'Show recently played queues',
                value: settings.showRecentQueues,
                onChanged: notifier.setShowRecentQueues,
              ),
              AppSettingsSwitch(
                icon: AppIcons.explore,
                searchId: 'appearance.for_you',
                title: 'For You',
                subtitle: 'Show recommended playlists',
                value: settings.showForYou,
                onChanged: notifier.setShowForYou,
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Interaction',
            icon: AppIcons.touchApp,
            children: [
              AppSettingsTile(
                icon: AppIcons.flashOn,
                searchId: 'appearance.quick_actions',
                title: 'Quick Actions',
                subtitle: 'Customize long-press actions',
                onTap: () =>
                    context.pushApp(const QuickActionsSettingsScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _customIntensityLabel(double value) {
  if (value <= 0.125) return 'Min';
  if (value <= 0.375) return 'Subtle';
  if (value <= 0.625) return 'Balanced';
  if (value <= 0.875) return 'Bold';
  return 'Max';
}

Widget _sliderLabel(BuildContext context, String text) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    ),
  );
}

/// A single motion-intensity row: dropdown + optional custom slider.
class _MotionIntensityRow extends StatelessWidget {
  final String id;
  final Color accent;
  final String title;
  final String subtitle;
  final PlayerMotionIntensity intensity;
  final double customIntensity;
  final ValueChanged<PlayerMotionIntensity> onIntensityChanged;
  final ValueChanged<double> onCustomChanged;

  const _MotionIntensityRow({
    required this.id,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.intensity,
    required this.customIntensity,
    required this.onIntensityChanged,
    required this.onCustomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppSettingsAnchor(
          id: id,
          child: AppListRow(
            dense: true,
            leading: AppRowIcon(
              icon: AppIcons.tune,
              color: accent,
              size: 40,
            ),
            title: title,
            subtitle: subtitle,
            trailing: DropdownButton<PlayerMotionIntensity>(
              value: intensity,
              underline: const SizedBox.shrink(),
              borderRadius: AppTokens.brMd,
              onChanged: (value) {
                if (value == null) return;
                onIntensityChanged(value);
              },
              items: const [
                DropdownMenuItem(
                  value: PlayerMotionIntensity.subtle,
                  child: Text('Subtle'),
                ),
                DropdownMenuItem(
                  value: PlayerMotionIntensity.balanced,
                  child: Text('Balanced'),
                ),
                DropdownMenuItem(
                  value: PlayerMotionIntensity.bold,
                  child: Text('Bold'),
                ),
                DropdownMenuItem(
                  value: PlayerMotionIntensity.custom,
                  child: Text('Custom'),
                ),
              ],
            ),
          ),
        ),
        if (intensity == PlayerMotionIntensity.custom)
          Padding(
            padding: const EdgeInsets.only(
              left: AppTokens.s3 + 40 + AppTokens.s3,
              right: AppTokens.s3,
              bottom: AppTokens.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accent,
                    thumbColor: accent,
                    inactiveTrackColor: accent.withValues(alpha: 0.2),
                    overlayColor: accent.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: customIntensity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 4,
                    label: _customIntensityLabel(customIntensity),
                    onChanged: onCustomChanged,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      _sliderLabel(context, 'Min'),
                      const Spacer(),
                      _sliderLabel(context, 'Subtle'),
                      const Spacer(),
                      _sliderLabel(context, 'Balanced'),
                      const Spacer(),
                      _sliderLabel(context, 'Bold'),
                      const Spacer(),
                      _sliderLabel(context, 'Max'),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

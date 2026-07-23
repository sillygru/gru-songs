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
import 'theme_selection_screen.dart';
import 'quick_actions_settings_screen.dart';

class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState
    extends ConsumerState<AppearanceSettingsScreen> {
  String _customIntensityLabel(double value) {
    if (value <= 0.125) return 'Min';
    if (value <= 0.375) return 'Subtle';
    if (value <= 0.625) return 'Balanced';
    if (value <= 0.875) return 'Bold';
    return 'Max';
  }

  Widget _sliderLabel(String text, double align) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final accent = AppTokens.accentOf(context, ref);

    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Appearance'),
      body: AppSettingsList(
        children: [
          AppSettingsGroup(
            label: 'Theme',
            icon: Icons.palette_outlined,
            children: [
              AppSettingsTile(
                icon: Icons.color_lens_outlined,
                title: 'App Theme',
                subtitle: 'Choose your visual style',
                onTap: () => context.pushApp(const ThemeSelectionScreen()),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Display',
            icon: Icons.view_list_rounded,
            children: [
              AppSettingsSwitch(
                icon: Icons.waves_rounded,
                title: 'Audio Visualizer',
                subtitle: 'Show animated wave while playing',
                value: settings.visualizerEnabled,
                onChanged: notifier.setVisualizerEnabled,
              ),
              AppSettingsSwitch(
                icon: Icons.graphic_eq_rounded,
                title: 'Waveform Progress Bar',
                subtitle: 'Show song waveform in player',
                value: settings.showWaveform,
                onChanged: notifier.setShowWaveform,
              ),
              AppSettingsSwitch(
                icon: Icons.timer_outlined,
                title: 'Show Song Duration',
                subtitle: 'Display duration in song lists',
                value: settings.showSongDuration,
                onChanged: notifier.setShowSongDuration,
              ),
              AppSettingsSwitch(
                icon: Icons.swap_vert_rounded,
                title: 'Auto-Hide Bottom Dock',
                subtitle: 'Hide on downward scroll, restore on upward scroll',
                value: settings.autoHideBottomBarOnScroll,
                onChanged: notifier.setAutoHideBottomBarOnScroll,
              ),
              AppSettingsSwitch(
                icon: Icons.blur_on_rounded,
                title: 'Lyrics blur overlay',
                subtitle: 'Progressive blur on the lyrics top and bottom edges',
                value: settings.lyricsBlurOverlayEnabled,
                onChanged: notifier.setLyricsBlurOverlayEnabled,
              ),
              AppSettingsSwitch(
                icon: Icons.blur_linear_rounded,
                title: 'Progressive blur on list headers',
                subtitle: 'Blur behind scrolling headers (performance heavy)',
                value: settings.showProgressiveBlurHeaders,
                onChanged: notifier.setProgressiveBlurHeaders,
              ),
              AppListRow(
                dense: true,
                leading: AppRowIcon(
                  icon: Icons.photo_size_select_large_outlined,
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
            ],
          ),
          AppSettingsGroup(
            label: 'Player motion',
            icon: Icons.graphic_eq_rounded,
            children: [
              AppSettingsSwitch(
                icon: Icons.album_outlined,
                title: 'Beat-reactive cover',
                subtitle: 'Album art pulses with the beat',
                value: settings.beatReactiveCoverEnabled,
                onChanged: notifier.setBeatReactiveCoverEnabled,
              ),
              AppSettingsSwitch(
                icon: Icons.auto_awesome_outlined,
                title: 'Beat-reactive particles',
                subtitle: 'Floating particles that drift and breathe with the '
                    'music',
                value: settings.beatReactiveParticlesEnabled,
                onChanged: notifier.setBeatReactiveParticlesEnabled,
              ),
              AppListRow(
                dense: true,
                leading: AppRowIcon(
                  icon: Icons.tune_rounded,
                  color: accent,
                  size: 40,
                ),
                title: 'Motion intensity',
                subtitle: 'How strongly the player reacts',
                trailing: DropdownButton<PlayerMotionIntensity>(
                  value: settings.playerMotionIntensity,
                  underline: const SizedBox.shrink(),
                  borderRadius: AppTokens.brMd,
                  onChanged: (value) {
                    if (value == null) return;
                    notifier.setPlayerMotionIntensity(value);
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
              if (settings.playerMotionIntensity ==
                  PlayerMotionIntensity.custom)
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
                          value: settings.playerMotionCustomIntensity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 4,
                          label: _customIntensityLabel(
                              settings.playerMotionCustomIntensity),
                          onChanged: (value) =>
                              notifier.setPlayerMotionCustomIntensity(value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            _sliderLabel('Min', 0.0),
                            const Spacer(),
                            _sliderLabel('Subtle', 0.25),
                            const Spacer(),
                            _sliderLabel('Balanced', 0.5),
                            const Spacer(),
                            _sliderLabel('Bold', 0.75),
                            const Spacer(),
                            _sliderLabel('Max', 1.0),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Output latency is a property of the listener's hardware, not the
              // app: Bluetooth typically runs 150-250ms behind wired. Without
              // this the pulse is permanently early on BT with no recourse.
              AppListRow(
                dense: true,
                leading: AppRowIcon(
                  icon: Icons.sync_alt_rounded,
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
            ],
          ),
          AppSettingsGroup(
            label: 'Home screen',
            icon: Icons.home_outlined,
            children: [
              AppSettingsSwitch(
                icon: Icons.auto_awesome_rounded,
                title: 'Quick Picks',
                subtitle: 'Show quick pick recommendations',
                value: settings.showQuickPicks,
                onChanged: notifier.setShowQuickPicks,
              ),
              AppSettingsSwitch(
                icon: Icons.history_rounded,
                title: 'Recent Queues',
                subtitle: 'Show recently played queues',
                value: settings.showRecentQueues,
                onChanged: notifier.setShowRecentQueues,
              ),
              AppSettingsSwitch(
                icon: Icons.explore_rounded,
                title: 'For You',
                subtitle: 'Show recommended playlists',
                value: settings.showForYou,
                onChanged: notifier.setShowForYou,
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Interaction',
            icon: Icons.touch_app_outlined,
            children: [
              AppSettingsTile(
                icon: Icons.flash_on_outlined,
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

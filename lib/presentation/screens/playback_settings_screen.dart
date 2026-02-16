import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';

class PlaybackSettingsScreen extends ConsumerStatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  ConsumerState<PlaybackSettingsScreen> createState() =>
      _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState
    extends ConsumerState<PlaybackSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Determine which mode is active
    final bool isGapMode = settings.delayDuration > 0;
    final bool isFadeMode =
        settings.fadeOutDuration > 0 || settings.fadeInDuration > 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Playback"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildSettingsGroup(
            title: 'Audio',
            icon: Icons.play_circle_outline,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.volume_off_rounded),
                title: const Text('Auto-Pause on Mute'),
                subtitle: const Text(
                  'Automatically pause playback when volume is 0',
                ),
                value: settings.autoPauseOnVolumeZero,
                onChanged: (val) {
                  ref
                      .read(settingsProvider.notifier)
                      .setAutoPauseOnVolumeZero(val);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_rounded),
                title: const Text('Auto-Resume on Unmute'),
                subtitle: const Text(
                  'Automatically resume playback when volume is restored',
                ),
                value: settings.autoResumeOnVolumeRestore,
                onChanged: (val) {
                  ref
                      .read(settingsProvider.notifier)
                      .setAutoResumeOnVolumeRestore(val);
                },
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'Transitions',
            icon: Icons.swap_horiz_rounded,
            children: [
              _buildDurationSlider(
                context: context,
                icon: Icons.hourglass_empty_rounded,
                title: 'Gap / Delay',
                subtitle: isFadeMode ? 'Disabled when fade is enabled' : null,
                value: settings.delayDuration,
                enabled: !isFadeMode,
                onChanged: isFadeMode
                    ? null
                    : (val) => ref
                        .read(settingsProvider.notifier)
                        .setDelayDuration(val),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildDurationSlider(
                context: context,
                icon: Icons.volume_down_rounded,
                title: 'Fade Out',
                subtitle: isGapMode ? 'Disabled when gap is enabled' : null,
                value: settings.fadeOutDuration,
                enabled: !isGapMode,
                onChanged: isGapMode
                    ? null
                    : (val) => ref
                        .read(settingsProvider.notifier)
                        .setFadeOutDuration(val),
              ),
              _buildDurationSlider(
                context: context,
                icon: Icons.volume_up_rounded,
                title: 'Fade In',
                subtitle: isGapMode ? 'Disabled when gap is enabled' : null,
                value: settings.fadeInDuration,
                enabled: !isGapMode,
                onChanged: isGapMode
                    ? null
                    : (val) => ref
                        .read(settingsProvider.notifier)
                        .setFadeInDuration(val),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({
    required String title,
    required List<Widget> children,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final List<Widget> childrenWithDividers = [];

    for (int i = 0; i < children.length; i++) {
      childrenWithDividers.add(children[i]);
      if (i < children.length - 1) {
        childrenWithDividers.add(
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.2,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: childrenWithDividers),
        ),
      ],
    );
  }

  Widget _buildDurationSlider({
    required BuildContext context,
    required IconData icon,
    required String title,
    required double value,
    bool enabled = true,
    String? subtitle,
    required ValueChanged<double>? onChanged,
  }) {
    final theme = Theme.of(context);
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : disabledColor,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: enabled ? null : disabledColor,
                ),
              ),
              const Spacer(),
              Text(
                '${value.toStringAsFixed(1)}s',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: enabled ? theme.colorScheme.primary : disabledColor,
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 32.0, top: 4.0),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: disabledColor),
              ),
            ),
          Slider(
            value: value,
            min: 0,
            max: 12,
            divisions: 24,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

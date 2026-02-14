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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Playback"),
        centerTitle: true,
      ),
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
                subtitle:
                    const Text('Automatically pause playback when volume is 0'),
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
                    'Automatically resume playback when volume is restored'),
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
                icon: Icons.volume_down_rounded,
                title: 'Fade Out',
                value: settings.fadeOutDuration,
                onChanged: (val) =>
                    ref.read(settingsProvider.notifier).setFadeOutDuration(val),
              ),
              _buildDurationSlider(
                context: context,
                icon: Icons.volume_up_rounded,
                title: 'Fade In',
                value: settings.fadeInDuration,
                onChanged: (val) =>
                    ref.read(settingsProvider.notifier).setFadeInDuration(val),
              ),
              _buildDurationSlider(
                context: context,
                icon: Icons.hourglass_empty_rounded,
                title: 'Gap / Delay',
                value: settings.delayDuration,
                onChanged: (val) =>
                    ref.read(settingsProvider.notifier).setDelayDuration(val),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: childrenWithDividers,
          ),
        ),
      ],
    );
  }

  Widget _buildDurationSlider({
    required BuildContext context,
    required IconData icon,
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                '${value.toStringAsFixed(1)}s',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
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

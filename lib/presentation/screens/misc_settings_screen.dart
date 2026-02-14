import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/telemetry_service.dart';

class MiscSettingsScreen extends ConsumerStatefulWidget {
  const MiscSettingsScreen({super.key});

  @override
  ConsumerState<MiscSettingsScreen> createState() => _MiscSettingsScreenState();
}

class _MiscSettingsScreenState extends ConsumerState<MiscSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Misc"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildSettingsGroup(
            title: 'Privacy',
            icon: Icons.security_outlined,
            children: [
              _buildTelemetryWidget(settings),
            ],
          ),
          _buildSettingsGroup(
            title: 'Behavior',
            icon: Icons.touch_app_outlined,
            children: [
              _buildPullToRefreshTile(),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTelemetryWidget(settings) {
    final levels = [
      'Level 0',
      'Level 1',
      'Level 2',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Text(
                'Telemetry Level',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
              ),
              const Spacer(),
              Text(
                levels[settings.telemetryLevel.clamp(0, 2)],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: settings.telemetryLevel.toDouble().clamp(0, 2),
            min: 0,
            max: 2,
            divisions: 2,
            label: levels[settings.telemetryLevel.clamp(0, 2)],
            onChanged: (val) {
              ref
                  .read(settingsProvider.notifier)
                  .setTelemetryLevel(val.toInt());
            },
          ),
          _buildLevelExplanation(settings.telemetryLevel.clamp(0, 2)),
        ],
      ),
    );
  }

  Widget _buildLevelExplanation(int level) {
    final explanations = [
      '• No data will be shared with developers.',
      '• Basic app information (version, platform).\n• App startup notification.',
      '• Everything in level 1.\n• Anonymous usage events (settings changed).\n• Library rescans and data management (import/export).',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        explanations[level],
        style: Theme.of(context).textTheme.bodySmall,
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

  Widget _buildPullToRefreshTile() {
    return FutureBuilder<bool>(
      future: ref.read(storageServiceProvider).getPullToRefreshEnabled(),
      builder: (context, snapshot) {
        return SwitchListTile(
          secondary: const Icon(Icons.touch_app_outlined),
          title: const Text('Pull to Refresh'),
          subtitle: const Text('Swipe down to refresh library'),
          value: snapshot.data ?? true,
          onChanged: (val) async {
            await ref.read(storageServiceProvider).setPullToRefreshEnabled(val);

            await TelemetryService.instance.trackEvent(
                'setting_changed',
                {
                  'setting': 'pull_to_refresh_enabled',
                  'value': val,
                },
                requiredLevel: 2);

            setState(() {});
          },
        );
      },
    );
  }
}

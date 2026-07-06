import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';

class MiscSettingsScreen extends ConsumerStatefulWidget {
  const MiscSettingsScreen({super.key});

  @override
  ConsumerState<MiscSettingsScreen> createState() => _MiscSettingsScreenState();
}

class _MiscSettingsScreenState extends ConsumerState<MiscSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final autoBackupState = ref.watch(autoBackupProvider);

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
            title: 'Backup',
            icon: Icons.backup_rounded,
            children: [
              _buildAutoBackupFrequencyTile(settings, autoBackupState),
              _buildAutoBackupDeleteAfterTile(settings),
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

  Widget _buildTelemetryWidget(SettingsState settings) {
    return SwitchListTile(
      secondary: const Icon(Icons.analytics_outlined),
      title: const Text('Telemetry'),
      subtitle: const Text(
        'Help improve Wispie with anonymous usage stats. '
        'No personal data is collected.',
      ),
      value: settings.telemetryEnabled,
      onChanged: (val) {
        ref.read(settingsProvider.notifier).setTelemetryEnabled(val);
      },
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
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildAutoBackupFrequencyTile(
      SettingsState settings, autoBackupState) {
    final frequencyOptions = {
      0: 'Disabled',
      24: 'Every 24 hours',
      48: 'Every 48 hours',
      72: 'Every 3 days',
      168: 'Every 7 days',
    };

    final currentLabel =
        frequencyOptions[settings.autoBackupFrequencyHours] ?? 'Disabled';

    return ListTile(
      leading: const Icon(Icons.backup_rounded),
      title: const Text('Auto Backup'),
      subtitle: Text('Frequency: $currentLabel'),
      trailing: DropdownButton<int>(
        value: settings.autoBackupFrequencyHours,
        underline: const SizedBox(),
        items: frequencyOptions.entries.map((entry) {
          return DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
        onChanged: (val) async {
          if (val != null) {
            await ref
                .read(settingsProvider.notifier)
                .setAutoBackupFrequencyHours(val);
            await ref.read(autoBackupProvider.notifier).setFrequencyHours(val);
          }
        },
      ),
    );
  }

  Widget _buildAutoBackupDeleteAfterTile(SettingsState settings) {
    final deleteOptions = {
      0: 'Never',
      7: '7 days',
      14: '14 days',
      30: '30 days',
      90: '90 days',
    };

    final currentLabel =
        deleteOptions[settings.autoBackupDeleteAfterDays] ?? 'Never';

    return ListTile(
      leading: const Icon(Icons.delete_outline_rounded),
      title: const Text('Auto-Delete Old Backups'),
      subtitle: Text('Delete backups older than: $currentLabel'),
      trailing: DropdownButton<int>(
        value: settings.autoBackupDeleteAfterDays,
        underline: const SizedBox(),
        items: deleteOptions.entries.map((entry) {
          return DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
        onChanged: (val) async {
          if (val != null) {
            await ref
                .read(settingsProvider.notifier)
                .setAutoBackupDeleteAfterDays(val);
            await ref.read(autoBackupProvider.notifier).setDeleteAfterDays(val);
          }
        },
      ),
    );
  }
}

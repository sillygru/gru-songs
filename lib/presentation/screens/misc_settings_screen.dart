import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../tokens/app_tokens.dart';

class MiscSettingsScreen extends ConsumerStatefulWidget {
  const MiscSettingsScreen({super.key});

  @override
  ConsumerState<MiscSettingsScreen> createState() => _MiscSettingsScreenState();
}

class _MiscSettingsScreenState extends ConsumerState<MiscSettingsScreen> {
  static const _frequencyOptions = {
    0: 'Disabled',
    24: 'Every 24 hours',
    48: 'Every 48 hours',
    72: 'Every 3 days',
    168: 'Every 7 days',
  };

  static const _deleteOptions = {
    0: 'Never',
    7: '7 days',
    14: '14 days',
    30: '30 days',
    90: '90 days',
  };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: const AppTopBar(title: 'Misc'),
      body: AppSettingsList(
        children: [
          AppSettingsGroup(
            label: 'Privacy',
            icon: Icons.security_outlined,
            children: [
              AppSettingsSwitch(
                icon: Icons.analytics_outlined,
                title: 'Telemetry',
                subtitle:
                    'Anonymous usage stats. No personal data is collected.',
                value: settings.telemetryEnabled,
                onChanged:
                    ref.read(settingsProvider.notifier).setTelemetryEnabled,
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Backup',
            icon: Icons.backup_rounded,
            children: [
              _dropdownRow(
                icon: Icons.backup_rounded,
                title: 'Auto Backup',
                subtitle: 'How often a backup is taken',
                value: settings.autoBackupFrequencyHours,
                options: _frequencyOptions,
                onChanged: (val) async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setAutoBackupFrequencyHours(val);
                  await ref
                      .read(autoBackupProvider.notifier)
                      .setFrequencyHours(val);
                },
              ),
              _dropdownRow(
                icon: Icons.delete_outline_rounded,
                title: 'Auto-Delete Old Backups',
                subtitle: 'Discard backups older than this',
                value: settings.autoBackupDeleteAfterDays,
                options: _deleteOptions,
                onChanged: (val) async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setAutoBackupDeleteAfterDays(val);
                  await ref
                      .read(autoBackupProvider.notifier)
                      .setDeleteAfterDays(val);
                },
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Behavior',
            icon: Icons.touch_app_outlined,
            children: [
              FutureBuilder<bool>(
                future:
                    ref.read(storageServiceProvider).getPullToRefreshEnabled(),
                builder: (context, snapshot) => AppSettingsSwitch(
                  icon: Icons.touch_app_outlined,
                  title: 'Pull to Refresh',
                  subtitle: 'Swipe down to refresh the library',
                  value: snapshot.data ?? true,
                  onChanged: (val) async {
                    await ref
                        .read(storageServiceProvider)
                        .setPullToRefreshEnabled(val);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdownRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required int value,
    required Map<int, String> options,
    required ValueChanged<int> onChanged,
  }) {
    final accent = AppTokens.accentOf(context, ref);

    return AppListRow(
      dense: true,
      leading: AppRowIcon(icon: icon, color: accent, size: 40),
      title: title,
      subtitle: subtitle,
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        borderRadius: AppTokens.brMd,
        style: AppTokens.rowSubtitle(context).copyWith(color: Colors.white),
        items: options.entries
            .map((entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)))
            .toList(),
        onChanged: (val) {
          if (val != null) onChanged(val);
        },
      ),
    );
  }
}

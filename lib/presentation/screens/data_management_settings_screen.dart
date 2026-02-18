import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/data_export_service.dart';
import '../../services/telemetry_service.dart';
import 'namida_import_screen.dart';
import 'backup_management_screen.dart';

class DataManagementSettingsScreen extends ConsumerStatefulWidget {
  const DataManagementSettingsScreen({super.key});

  @override
  ConsumerState<DataManagementSettingsScreen> createState() =>
      _DataManagementSettingsScreenState();
}

class _DataManagementSettingsScreenState
    extends ConsumerState<DataManagementSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Data Management"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildSettingsGroup(
            title: 'Backup & Restore',
            icon: Icons.backup_rounded,
            children: [
              _buildListTile(
                icon: Icons.upload_file_rounded,
                title: 'Export App Data',
                subtitle: 'Backup your stats, favorites, and playlists',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final exportService = DataExportService();
                    await exportService.exportUserData();

                    TelemetryService.instance.trackEvent(
                        'data_management',
                        {
                          'action': 'export_data',
                        },
                        requiredLevel: 2);
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text("Export failed: $e")),
                      );
                    }
                  }
                },
              ),
              _buildListTile(
                icon: Icons.download_for_offline_rounded,
                title: 'Import App Data',
                subtitle: 'Restore or merge data from a backup',
                onTap: () => _handleImport(),
              ),
              _buildListTile(
                icon: Icons.download_rounded,
                title: 'Import from Namida',
                subtitle: 'Import playlists and favorites from Namida',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NamidaImportScreen()),
                  );
                },
              ),
              _buildListTile(
                icon: Icons.backup_rounded,
                title: 'Manage Backups',
                subtitle: 'Create, restore, and manage app backups',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BackupManagementScreen()),
                  );
                },
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

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading:
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Future<void> _handleImport() async {
    try {
      final exportService = DataExportService();
      final validation = await exportService.validateBackup();

      if (validation == null) return;

      if (!validation['valid']) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Invalid Backup"),
              content: Text(validation['error']),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mounted) {
        final strategy = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Import Strategy"),
            content: const Text(
                "How would you like to import this data?\n\nAdditive: Add to your existing stats and data without duplicates.\n\nReplace: Wipe your current stats and data and replace them with the backup."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, "additive"),
                child: const Text("ADDITIVE"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, "replace"),
                child: const Text("REPLACE STATS"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL"),
              ),
            ],
          ),
        );

        if (strategy == null) return;

        final additive = strategy == "additive";

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );
        }

        await exportService.performImport(
          statsDbPath: validation['statsDbPath'],
          dataDbPath: validation['dataDbPath'],
          additive: additive,
        );

        TelemetryService.instance.trackEvent(
            'data_management',
            {
              'action': 'import_data',
              'strategy': strategy,
            },
            requiredLevel: 2);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Import successful!")),
          );
          ref.invalidate(userDataProvider);
          ref.invalidate(songsProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import failed: $e")),
        );
      }
    }
  }
}

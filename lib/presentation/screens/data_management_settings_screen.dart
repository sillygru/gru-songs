import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/data_export_service.dart';
import '../../services/telemetry_service.dart';
import '../../services/database_optimizer_service.dart';
import '../widgets/optimization_options_dialog.dart';
import 'namida_import_screen.dart';

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
                      ScaffoldMessenger.of(context).showSnackBar(
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
            ],
          ),
          _buildSettingsGroup(
            title: 'Maintenance',
            icon: Icons.build_rounded,
            children: [
              _buildListTile(
                icon: Icons.search_rounded,
                title: 'Re-index All',
                subtitle: 'Rebuild search index from cached songs',
                onTap: () => _showReindexDialog(),
              ),
              _buildListTile(
                icon: Icons.build_rounded,
                title: 'Optimize Database',
                subtitle: 'Check and fix database issues',
                onTap: () => _showOptimizeDatabaseDialog(),
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

  Future<void> _showReindexDialog() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.search_rounded, color: Colors.blue, size: 48),
        title: const Text('Re-index Search Data'),
        content: const Text(
          'This will rebuild the search index from your cached songs.\n\n'
          'This operation is faster than full database optimization and only affects search functionality.\n\n'
          'Would you like to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-index'),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Re-indexing search data...'),
          ],
        ),
      ),
    );

    try {
      final optimizer = DatabaseOptimizerService();
      final result = await optimizer.reindexSearchOnly();

      if (mounted) {
        Navigator.pop(context);

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : Colors.red,
              size: 48,
            ),
            title: Text(
                result.success ? 'Re-indexing Complete' : 'Re-indexing Issues'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.message),
                  if (result.issuesFound.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Issues Found:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...result.issuesFound.map((issue) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(issue)),
                            ],
                          ),
                        )),
                  ],
                  if (result.fixesApplied.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Operations Performed:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...result.fixesApplied.map((fix) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check,
                                  size: 16, color: Colors.green),
                              const SizedBox(width: 4),
                              Expanded(child: Text(fix)),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error, color: Colors.red, size: 48),
            title: const Text('Re-indexing Failed'),
            content: Text('An error occurred during re-indexing: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
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

  Future<void> _showRestartDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt, color: Colors.blue, size: 48),
        title: const Text('Restart Required'),
        content: const Text(
          'Database optimization has been completed successfully.\n\n'
          'The app needs to restart to apply all changes properly.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _restartApp();
            },
            child: const Text('Restart Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _restartApp() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('gru_songs/app');
        await platform.invokeMethod('restartApp');
      } catch (e) {
        exit(0);
      }
    } else {
      exit(0);
    }
  }

  Future<void> _showOptimizeDatabaseDialog() async {
    final options = await showDialog<OptimizationOptions>(
      context: context,
      builder: (context) => const OptimizationOptionsDialog(),
    );

    if (options == null || !mounted) return;

    final progressNotifier = ValueNotifier<double>(0.0);
    final messageNotifier = ValueNotifier<String>('Starting optimization...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: messageNotifier,
              builder: (context, message, _) =>
                  Text(message, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) =>
                  LinearProgressIndicator(value: progress),
            ),
          ],
        ),
      ),
    );

    try {
      final optimizer = DatabaseOptimizerService();
      final result = await optimizer.optimizeDatabases(
        options: options,
        onProgress: (message, progress) {
          messageNotifier.value = message;
          progressNotifier.value = progress;
        },
      );

      if (mounted) {
        Navigator.pop(context);

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : Colors.red,
              size: 48,
            ),
            title: Text(result.success
                ? 'Optimization Complete'
                : 'Optimization Issues'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.message),
                  if (result.issuesFound.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Issues Found:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...result.issuesFound.map((issue) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(issue)),
                            ],
                          ),
                        )),
                  ],
                  if (result.fixesApplied.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Fixes Applied:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...result.fixesApplied.map((fix) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check,
                                  size: 16, color: Colors.green),
                              const SizedBox(width: 4),
                              Expanded(child: Text(fix)),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (result.fixesApplied.isNotEmpty) {
          ref.invalidate(userDataProvider);

          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showRestartDialog();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error, color: Colors.red, size: 48),
            title: const Text('Optimization Failed'),
            content: Text('An error occurred during optimization: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import 'storage_management_screen.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../services/android_storage_service.dart';
import '../../services/data_export_service.dart';
import '../../services/telemetry_service.dart';
import '../../services/database_optimizer_service.dart';
import 'theme_selection_screen.dart';
import 'namida_import_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _selectMusicFolder() async {
    if (Platform.isAndroid) {
      final selection = await AndroidStorageService.pickTree();
      if (selection == null) return;
      if (selection.path == null || selection.path!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unable to access selected folder")),
          );
        }
        return;
      }
      final storage = ref.read(storageServiceProvider);
      await storage.setMusicFolderTreeUri(selection.treeUri);
      await storage.setMusicFolderPath(selection.path!);
      ref.invalidate(songsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Music folder updated")));
      }
      return;
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;
    final storage = ref.read(storageServiceProvider);
    await storage.setMusicFolderPath(selectedDirectory);
    ref.invalidate(songsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Music folder updated")));
    }
  }

  Future<void> _selectLyricsFolder() async {
    if (Platform.isAndroid) {
      final selection = await AndroidStorageService.pickTree();
      if (selection == null) return;
      if (selection.path == null || selection.path!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unable to access selected folder")),
          );
        }
        return;
      }
      final storage = ref.read(storageServiceProvider);
      await storage.setLyricsFolderTreeUri(selection.treeUri);
      await storage.setLyricsFolderPath(selection.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lyrics folder updated")));
      }
      return;
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;
    final storage = ref.read(storageServiceProvider);
    await storage.setLyricsFolderPath(selectedDirectory);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Lyrics folder updated")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSettingsGroup(
            title: 'Appearance',
            children: [
              _buildListTile(
                icon: Icons.palette_outlined,
                title: 'App Theme',
                subtitle: 'Choose your visual style',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ThemeSelectionScreen()),
                  );
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.timer_outlined),
                title: const Text('Show Song Duration'),
                subtitle: const Text('Display duration in song lists'),
                value: settings.showSongDuration,
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).setShowSongDuration(val);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.waves_rounded),
                title: const Text('Audio Visualizer'),
                subtitle: const Text('Show animated wave while playing'),
                value: settings.visualizerEnabled,
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).setVisualizerEnabled(val);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_off_rounded),
                title: const Text('Auto-Pause on Mute'),
                subtitle: const Text(
                    'Automatically pause playback when volume is set to 0'),
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
                    'Automatically resume playback when volume is restored from 0'),
                value: settings.autoResumeOnVolumeRestore,
                onChanged: (val) {
                  ref
                      .read(settingsProvider.notifier)
                      .setAutoResumeOnVolumeRestore(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsGroup(
            title: 'Storage & Folders',
            children: [
              FutureBuilder<String?>(
                  future: ref.read(storageServiceProvider).getMusicFolderPath(),
                  builder: (context, snapshot) {
                    return _buildListTile(
                      icon: Icons.library_music_outlined,
                      title: 'Music Folder',
                      subtitle: snapshot.data ?? 'Not selected',
                      onTap: _selectMusicFolder,
                    );
                  }),
              FutureBuilder<String?>(
                  future:
                      ref.read(storageServiceProvider).getLyricsFolderPath(),
                  builder: (context, snapshot) {
                    return _buildListTile(
                      icon: Icons.lyrics_outlined,
                      title: 'Lyrics Folder',
                      subtitle: snapshot.data ?? 'Not selected (Optional)',
                      onTap: _selectLyricsFolder,
                    );
                  }),
              _buildListTile(
                icon: Icons.storage_outlined,
                title: 'Manage Storage',
                subtitle: 'Disk usage and data management',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StorageManagementScreen()),
                  );
                },
              ),
              _buildListTile(
                icon: Icons.refresh_rounded,
                title: 'Re-scan Library Now',
                subtitle: 'Manually refresh all songs from disk',
                onTap: () {
                  ref.read(songsProvider.notifier).forceFullScan();

                  TelemetryService.instance.trackEvent(
                      'library_action',
                      {
                        'action': 'force_full_scan',
                      },
                      requiredLevel: 2);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Scanning library...")),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTelemetrySettings(),
          const SizedBox(height: 16),
          _buildDataManagementSettings(),
          const SizedBox(height: 16),
          _buildPullToRefreshSettings(),
        ],
      ),
    );
  }

  Widget _buildDataManagementSettings() {
    final authState = ref.watch(authProvider);
    final username = authState.username;

    return _buildSettingsGroup(
      title: 'Data Management',
      children: [
        _buildListTile(
          icon: Icons.upload_file_rounded,
          title: 'Export App Data',
          subtitle: 'Backup your stats, favorites, and playlists to a .zip',
          onTap: () async {
            if (username == null) return;
            try {
              final exportService = DataExportService();
              await exportService.exportUserData(username);

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
          subtitle: 'Restore or merge data from a backup .zip',
          onTap: () => _handleImport(),
        ),
        _buildListTile(
          icon: Icons.download_rounded,
          title: 'Import from Namida',
          subtitle: 'Import playlists and favorites from Namida backup',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NamidaImportScreen()),
            );
          },
        ),
        _buildListTile(
          icon: Icons.build_rounded,
          title: 'Optimize Database',
          subtitle: 'Check and fix database issues',
          onTap: () => _showOptimizeDatabaseDialog(),
        ),
        _buildListTile(
          icon: Icons.search_rounded,
          title: 'Re-index All',
          subtitle: 'Rebuild search index without full optimization',
          onTap: () => _showReindexDialog(),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    final authState = ref.watch(authProvider);
    final username = authState.username;
    if (username == null) return;

    try {
      final exportService = DataExportService();
      final validation = await exportService.validateBackup(username);

      if (validation == null) return; // Picked nothing

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

      // Valid backup, ask for merge strategy
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

        // Show loading
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );
        }

        await exportService.performImport(
          username: username,
          importPath: validation['importPath'],
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
          Navigator.pop(context); // Pop loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Import successful!")),
          );
          // Invalidate providers to refresh data
          ref.invalidate(userDataProvider);
          ref.invalidate(songsProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        // Try to pop loading if it's there
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
    // For Android, we can use a platform channel to restart the app
    // For other platforms, we just exit and let the user relaunch
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('gru_songs/app');
        await platform.invokeMethod('restartApp');
      } catch (e) {
        // If platform method fails, just exit
        exit(0);
      }
    } else {
      // On other platforms, just exit
      exit(0);
    }
  }

  Future<void> _showReindexDialog() async {
    final authState = ref.read(authProvider);
    final username = authState.username;
    if (username == null) return;

    // Show confirmation dialog
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

    // Show loading dialog
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
      final result = await optimizer.reindexSearchOnly(username);

      if (mounted) {
        Navigator.pop(context); // Pop loading

        // Show results
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
        Navigator.pop(context); // Pop loading
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

  Future<void> _showOptimizeDatabaseDialog() async {
    final authState = ref.read(authProvider);
    final username = authState.username;
    if (username == null) return;

    // Show backup warning first
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 48),
        title: const Text('Backup Recommended'),
        content: const Text(
          'Database optimization will check for and fix missing tables, corrupted data, orphaned records, and duplicates.\n\n'
          'While this process is generally safe, it is recommended to create a backup first.\n\n'
          'Would you like to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    final progressNotifier = ValueNotifier<double>(0.0);
    final messageNotifier = ValueNotifier<String>('Starting optimization...');

    // Show loading dialog
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
        username,
        onProgress: (message, progress) {
          messageNotifier.value = message;
          progressNotifier.value = progress;
        },
      );

      if (mounted) {
        Navigator.pop(context); // Pop loading

        // Show results
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

        // Refresh providers if fixes were applied
        if (result.fixesApplied.isNotEmpty) {
          ref.invalidate(userDataProvider);

          // Show restart dialog after a brief delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showRestartDialog();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading
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

  Widget _buildTelemetrySettings() {
    final settings = ref.watch(settingsProvider);
    final levels = [
      'Level 0',
      'Level 1',
      'Level 2',
    ];

    return _buildSettingsGroup(
      title: 'Telemetry',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share anonymous data with developers?',
                style: TextStyle(fontWeight: FontWeight.w500),
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
              Center(
                child: Text(
                  levels[settings.telemetryLevel.clamp(0, 2)],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildLevelExplanation(settings.telemetryLevel.clamp(0, 2)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
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
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        explanations[level],
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildSettingsGroup(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildPullToRefreshSettings() {
    return FutureBuilder<bool>(
      future: ref.read(storageServiceProvider).getIsLocalMode(),
      builder: (context, snapshot) {
        return _buildSettingsGroup(
          title: 'Pull to Refresh',
          children: [
            FutureBuilder<bool>(
              future:
                  ref.read(storageServiceProvider).getPullToRefreshEnabled(),
              builder: (context, snapshot) {
                return SwitchListTile(
                  secondary: const Icon(Icons.touch_app_outlined),
                  title: const Text('Enable Pull to Refresh'),
                  value: snapshot.data ?? true,
                  onChanged: (val) async {
                    await ref
                        .read(storageServiceProvider)
                        .setPullToRefreshEnabled(val);

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
            ),
          ],
        );
      },
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }
}

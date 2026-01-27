import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/providers.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'cache_management_screen.dart';
import '../widgets/scanning_progress_bar.dart';
import '../../services/android_storage_service.dart';
import '../../services/data_export_service.dart';
import '../../services/telemetry_service.dart';

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

  void _showThemeSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(builder: (context, ref, child) {
          final currentTheme = ref.watch(themeProvider);
          return AlertDialog(
            title: const Text("Select Theme"),
            content: RadioGroup<GruThemeMode>(
              groupValue: currentTheme.mode,
              onChanged: (val) {
                if (val != null) {
                  ref.read(themeProvider.notifier).setTheme(val);
                  Navigator.pop(context);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var theme in GruThemeMode.values)
                    RadioListTile<GruThemeMode>(
                      title:
                          Text(theme.toString().split('.').last.toUpperCase()),
                      value: theme,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          );
        });
      },
    );
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
                onTap: () => _showThemeSelector(context),
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
                title: 'Manage Cache',
                subtitle: 'Internal app cache management',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CacheManagementScreen()),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/data_export_service.dart';
import '../../services/telemetry_service.dart';
import 'namida_import_screen.dart';
import 'backup_management_screen.dart';
import 'storage_management_screen.dart';

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
                    final options = await _showExportOptionsDialog();
                    if (options == null) return;

                    final exportService = DataExportService();
                    await exportService.exportUserData(options: options);

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
                subtitle: 'Restore data from a backup (replaces all)',
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
          _buildSettingsGroup(
            title: 'Storage',
            icon: Icons.storage_outlined,
            children: [
              _buildListTile(
                icon: Icons.storage_rounded,
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
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<ExportOptions?> _showExportOptionsDialog() async {
    final selectedTypes = <ExportContentType>{
      ExportContentType.userStats,
      ExportContentType.userData,
      ExportContentType.userSettings,
    };

    return showDialog<ExportOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Export Options"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select content to export:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  _buildExportCheckbox(
                    title: 'User Stats',
                    subtitle: 'Play counts, sessions, fun stats',
                    value: selectedTypes.contains(ExportContentType.userStats),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.userStats);
                        } else {
                          selectedTypes.remove(ExportContentType.userStats);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'User Data',
                    subtitle: 'Favorites, hidden, playlists, moods',
                    value: selectedTypes.contains(ExportContentType.userData),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.userData);
                        } else {
                          selectedTypes.remove(ExportContentType.userData);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'User Settings',
                    subtitle: 'Theme, sort order, preferences',
                    value:
                        selectedTypes.contains(ExportContentType.userSettings),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.userSettings);
                        } else {
                          selectedTypes.remove(ExportContentType.userSettings);
                        }
                      });
                    },
                  ),
                  const Divider(height: 24),
                  _buildExportCheckbox(
                    title: 'Cover Cache',
                    subtitle: 'Album artwork images',
                    value: selectedTypes.contains(ExportContentType.coverCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.coverCache);
                        } else {
                          selectedTypes.remove(ExportContentType.coverCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Library Cache',
                    subtitle: 'Cached song metadata',
                    value:
                        selectedTypes.contains(ExportContentType.libraryCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.libraryCache);
                        } else {
                          selectedTypes.remove(ExportContentType.libraryCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Search Index',
                    subtitle: 'Indexed search data',
                    value:
                        selectedTypes.contains(ExportContentType.searchIndex),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.searchIndex);
                        } else {
                          selectedTypes.remove(ExportContentType.searchIndex);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Waveform Cache',
                    subtitle: 'Audio waveform data',
                    value:
                        selectedTypes.contains(ExportContentType.waveformCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.waveformCache);
                        } else {
                          selectedTypes.remove(ExportContentType.waveformCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Color Cache',
                    subtitle: 'Album color themes',
                    value: selectedTypes.contains(ExportContentType.colorCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.colorCache);
                        } else {
                          selectedTypes.remove(ExportContentType.colorCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Lyrics Cache',
                    subtitle: 'Stored lyrics data',
                    value:
                        selectedTypes.contains(ExportContentType.lyricsCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(ExportContentType.lyricsCache);
                        } else {
                          selectedTypes.remove(ExportContentType.lyricsCache);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL"),
              ),
              TextButton(
                onPressed: selectedTypes.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context, ExportOptions(contentTypes: selectedTypes)),
                child: const Text("EXPORT"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExportCheckbox({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
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

  Future<Map<String, dynamic>?> _showImportSelectionDialog(
      Map<String, dynamic> validation) async {
    bool importUserData = validation['hasUserDataJson'] ?? false;
    bool importShuffleState = validation['hasShuffleStateJson'] ?? false;
    bool importPlaybackState = validation['hasPlaybackStateJson'] ?? false;
    bool importAppSettings = validation['hasAppSettingsJson'] ?? false;
    bool importQueueHistory = validation['hasQueueHistoryJson'] ?? false;
    bool importMergedGroups = validation['hasMergedGroupsJson'] ?? false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Select Data to Import"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Choose which data to import from the backup:",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                if (validation['hasUserDataJson'] ?? false)
                  _buildImportCheckbox(
                    "User Data",
                    "Favorites, playlists, preferences",
                    importUserData,
                    (v) => setDialogState(() => importUserData = v),
                  ),
                if (validation['hasShuffleStateJson'] ?? false)
                  _buildImportCheckbox(
                    "Shuffle Configuration",
                    "Shuffle personality and settings",
                    importShuffleState,
                    (v) => setDialogState(() => importShuffleState = v),
                  ),
                if (validation['hasAppSettingsJson'] ?? false)
                  _buildImportCheckbox(
                    "App Settings",
                    "Quick actions, theme, sort order",
                    importAppSettings,
                    (v) => setDialogState(() => importAppSettings = v),
                  ),
                if (validation['hasPlaybackStateJson'] ?? false)
                  _buildImportCheckbox(
                    "Playback State",
                    "Current queue and position",
                    importPlaybackState,
                    (v) => setDialogState(() => importPlaybackState = v),
                  ),
                if (validation['hasQueueHistoryJson'] ?? false)
                  _buildImportCheckbox(
                    "Queue History",
                    "Past queues",
                    importQueueHistory,
                    (v) => setDialogState(() => importQueueHistory = v),
                  ),
                if (validation['hasMergedGroupsJson'] ?? false)
                  _buildImportCheckbox(
                    "Merged Groups",
                    "Song groupings",
                    importMergedGroups,
                    (v) => setDialogState(() => importMergedGroups = v),
                  ),
                if (validation['hasUserDataJson'] == false &&
                    validation['hasShuffleStateJson'] == false &&
                    validation['hasAppSettingsJson'] == false &&
                    validation['hasPlaybackStateJson'] == false &&
                    validation['hasQueueHistoryJson'] == false &&
                    validation['hasMergedGroupsJson'] == false)
                  const Text(
                    "No additional data files found in backup.",
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("CANCEL"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'importUserData': importUserData,
                'importShuffleState': importShuffleState,
                'importPlaybackState': importPlaybackState,
                'importAppSettings': importAppSettings,
                'importQueueHistory': importQueueHistory,
                'importMergedGroups': importMergedGroups,
              }),
              child: const Text("IMPORT"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCheckbox(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import Data"),
        content: const Text(
          "This will replace ALL existing data with the imported data.\n\n"
          "Your current stats, favorites, playlists, and settings will be overwritten.\n\n"
          "This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("CONTINUE"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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

      final importOptions = await _showImportSelectionDialog(
        validation.cast<String, dynamic>(),
      );

      if (importOptions == null) return;

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
        additive: false,
        importUserData: importOptions['importUserData'],
        importShuffleState: importOptions['importShuffleState'],
        importPlaybackState: importOptions['importPlaybackState'],
        importAppSettings: importOptions['importAppSettings'],
        importQueueHistory: importOptions['importQueueHistory'],
        importMergedGroups: importOptions['importMergedGroups'],
      );

      TelemetryService.instance.trackEvent(
          'data_management',
          {
            'action': 'import_data',
            'strategy': 'replace',
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

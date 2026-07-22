import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/backup_service.dart';
import '../../services/import_options.dart';
import '../../presentation/widgets/import_options_dialog.dart';
import 'namida_import_screen.dart';
import 'backup_management_screen.dart';
import 'storage_management_screen.dart';
import '../components/app_surface.dart';
import '../components/app_feedback.dart';

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

                    await BackupService.instance
                        .exportUserData(options: options);
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

  Future<BackupOptions?> _showExportOptionsDialog() async {
    final selectedTypes = <BackupContentType>{
      BackupContentType.userStats,
      BackupContentType.userData,
      BackupContentType.userSettings,
    };

    return showDialog<BackupOptions>(
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
                    value: selectedTypes.contains(BackupContentType.userStats),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.userStats);
                        } else {
                          selectedTypes.remove(BackupContentType.userStats);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'User Data',
                    subtitle: 'Favorites, hidden, playlists, moods',
                    value: selectedTypes.contains(BackupContentType.userData),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.userData);
                        } else {
                          selectedTypes.remove(BackupContentType.userData);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'User Settings',
                    subtitle: 'Theme, sort order, preferences',
                    value:
                        selectedTypes.contains(BackupContentType.userSettings),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.userSettings);
                        } else {
                          selectedTypes.remove(BackupContentType.userSettings);
                        }
                      });
                    },
                  ),
                  const Divider(height: 24),
                  _buildExportCheckbox(
                    title: 'Cover Cache',
                    subtitle: 'Album artwork images',
                    value: selectedTypes.contains(BackupContentType.coverCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.coverCache);
                        } else {
                          selectedTypes.remove(BackupContentType.coverCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Library Cache',
                    subtitle: 'Cached song metadata',
                    value:
                        selectedTypes.contains(BackupContentType.libraryCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.libraryCache);
                        } else {
                          selectedTypes.remove(BackupContentType.libraryCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Search Index',
                    subtitle: 'Indexed search data',
                    value:
                        selectedTypes.contains(BackupContentType.searchIndex),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.searchIndex);
                        } else {
                          selectedTypes.remove(BackupContentType.searchIndex);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Waveform Cache',
                    subtitle: 'Audio waveform data',
                    value:
                        selectedTypes.contains(BackupContentType.waveformCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.waveformCache);
                        } else {
                          selectedTypes.remove(BackupContentType.waveformCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Color Cache',
                    subtitle: 'Album color themes',
                    value: selectedTypes.contains(BackupContentType.colorCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.colorCache);
                        } else {
                          selectedTypes.remove(BackupContentType.colorCache);
                        }
                      });
                    },
                  ),
                  _buildExportCheckbox(
                    title: 'Lyrics Cache',
                    subtitle: 'Stored lyrics data',
                    value:
                        selectedTypes.contains(BackupContentType.lyricsCache),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedTypes.add(BackupContentType.lyricsCache);
                        } else {
                          selectedTypes.remove(BackupContentType.lyricsCache);
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
                        context, BackupOptions(contentTypes: selectedTypes)),
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
        AppSurface(
          padding: EdgeInsets.zero,
          clipContent: true,
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

    Map<String, dynamic>? validation;
    try {
      validation = await BackupService.instance.pickAndValidateBackup();

      if (validation == null) return;

      final availableCategories =
          BackupService.instance.getAvailableCategories(validation);

      if (!mounted) {
        await BackupService.instance.discardValidation(validation);
        return;
      }

      final importOptions = await showDialog<ImportOptions>(
        context: context,
        builder: (context) => ImportOptionsDialog(
          availableCategories: availableCategories,
          defaultAdditive: false,
          defaultRestoreDatabases: true,
        ),
      );

      if (importOptions == null) {
        await BackupService.instance.discardValidation(validation);
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      await BackupService.instance.performImport(
        validation: validation,
        options: importOptions,
      );

      if (mounted) {
        Navigator.pop(context);
        appSnack(context, "Import successful!");
        ref.invalidate(userDataProvider);
        ref.invalidate(songsProvider);
      }
    } catch (e) {
      await BackupService.instance.discardValidation(validation);
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        appSnack(context, "Import failed: $e");
      }
    }
  }
}

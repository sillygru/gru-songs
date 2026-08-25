import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/backup_service.dart';
import '../../services/import_options.dart';
import '../../presentation/widgets/import_options_dialog.dart';
import '../../presentation/widgets/import_progress_dialog.dart';
import 'backup_management_screen.dart';
import 'storage_management_screen.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../components/app_feedback.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_icons.dart';

class DataManagementSettingsScreen extends ConsumerStatefulWidget {
  /// Row to reveal when opened from settings search.
  final String? highlightId;

  const DataManagementSettingsScreen({super.key, this.highlightId});

  @override
  ConsumerState<DataManagementSettingsScreen> createState() =>
      _DataManagementSettingsScreenState();
}

class _DataManagementSettingsScreenState
    extends ConsumerState<DataManagementSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Data Management'),
      body: AppSettingsList(
        highlightId: widget.highlightId,
        children: [
          AppSettingsGroup(
            label: 'Backup & Restore',
            icon: AppIcons.cloudUpload,
            children: [
              AppSettingsTile(
                searchId: 'data.export',
                icon: AppIcons.upload,
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
                    messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                },
              ),
              AppSettingsTile(
                searchId: 'data.import',
                icon: AppIcons.download,
                title: 'Import App Data',
                subtitle: 'Restore data from a backup (replaces all)',
                onTap: () => _handleImport(),
              ),
              AppSettingsTile(
                searchId: 'data.backups',
                icon: AppIcons.cloudUpload,
                title: 'Manage Backups',
                subtitle: 'Create, restore, and manage app backups',
                onTap: () => context.pushApp(const BackupManagementScreen()),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Storage',
            icon: AppIcons.storage,
            children: [
              AppSettingsTile(
                searchId: 'data.storage',
                icon: AppIcons.storage,
                title: 'Manage Storage',
                subtitle: 'Disk usage and data management',
                onTap: () => context.pushApp(const StorageManagementScreen()),
              ),
            ],
          ),
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
                    subtitle: 'Favorites, hidden, playlists',
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
          defaultRestoreDatabases: true,
        ),
      );

      if (importOptions == null) {
        await BackupService.instance.discardValidation(validation);
        return;
      }

      final progress = ValueNotifier<ImportProgress>(
        const ImportProgress(progress: 0, label: 'Importing…'),
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ImportProgressDialog(
            progress: progress,
            title: 'Importing data',
          ),
        );
      }

      await BackupService.instance.performImport(
        validation: validation,
        options: importOptions,
        onProgress: (value, label) =>
            progress.value = ImportProgress(progress: value, label: label),
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

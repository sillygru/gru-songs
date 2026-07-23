import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../services/backup_service.dart';
import '../../services/database_service.dart';
import '../../services/import_options.dart';
import '../../services/storage_service.dart';
import '../../presentation/widgets/import_options_dialog.dart';
import '../../presentation/widgets/backup_options_dialog.dart';
import '../../providers/providers.dart';
import '../components/app_surface.dart';
import '../tokens/app_tokens.dart';
import '../components/app_feedback.dart';

class BackupManagementScreen extends ConsumerStatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  ConsumerState<BackupManagementScreen> createState() =>
      _BackupManagementScreenState();
}

class _BackupManagementScreenState
    extends ConsumerState<BackupManagementScreen> {
  List<BackupInfo> _backups = [];
  bool _isLoading = true;
  bool _isCreatingBackup = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final backups = await BackupService.instance.getBackupsList();
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        appSnack(context, 'Error loading backups: $e');
      }
    }
  }

  Future<void> _createBackup() async {
    final options = await _showBackupOptionsDialog();
    if (options == null) return;

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final audioManager = ref.read(audioPlayerManagerProvider);
      await audioManager.forceFlushCurrentStats();
      await audioManager.savePlaybackState();
      final backupFilename = await BackupService.instance.createBackup(options);
      await _loadBackups();

      if (mounted) {
        appSnack(context, 'Backup created: $backupFilename');
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Failed to create backup: $e');
      }
    } finally {
      setState(() {
        _isCreatingBackup = false;
      });
    }
  }

  Future<BackupOptions?> _showBackupOptionsDialog() async {
    final storage = StorageService();
    final initialTypes = await storage.loadManualBackupContentTypes();
    if (!mounted) return null;

    final options = await showDialog<BackupOptions>(
      context: context,
      builder: (context) =>
          BackupOptionsDialog(initialTypes: initialTypes),
    );

    if (options != null) {
      await storage.saveManualBackupContentTypes(options.contentTypes);
    }
    return options;
  }

  Future<void> _restoreBackup(BackupInfo backupInfo) async {
    // Inspect the backup being restored — not a file the user picks — so the
    // offered categories always match what actually gets restored.
    Map<String, dynamic> validation;
    try {
      validation =
          await BackupService.instance.validateBackupFile(backupInfo.file);
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Failed to validate backup: $e');
      }
      return;
    }

    final availableCategories =
        BackupService.instance.getAvailableCategories(validation);
    await BackupService.instance.discardValidation(validation);

    if (!mounted) return;

    final importOptions = await showDialog<ImportOptions>(
      context: context,
      builder: (context) => ImportOptionsDialog(
        availableCategories: availableCategories,
        defaultAdditive: false,
        defaultRestoreDatabases: true,
      ),
    );

    if (importOptions == null) return;

    if (!mounted) return;

    if (importOptions.restoreDatabases &&
        importOptions.categories.length >= ImportDataCategory.values.length) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('DANGER: Full Data Replace'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Are you absolutely sure you want to restore from ${backupInfo.displayName}?'),
              const SizedBox(height: 16),
              const Text(
                'WARNING: This will COMPLETELY REPLACE all your current data:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTokens.danger),
              ),
              const SizedBox(height: 8),
              const Text('• All your current statistics and play history'),
              const Text('• All your favorites and playlists'),
              const Text('• All your hidden songs and preferences'),
              const Text('• All your current settings and state'),
              const SizedBox(height: 12),
              const Text(
                'YOUR CURRENT DATA WILL BE PERMANENTLY LOST!',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTokens.danger),
              ),
              const SizedBox(height: 8),
              const Text('There is NO way to undo this action.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                backgroundColor: AppTokens.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('YES, REPLACE EVERYTHING'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Restoring data...'),
            ],
          ),
        ),
      );
    }

    try {
      await BackupService.instance
          .restoreFromBackup(backupInfo, options: importOptions);

      final songs = await DatabaseService.instance.getAllSongs();
      await ref.read(audioPlayerManagerProvider).init(songs);

      await ref.read(userDataProvider.notifier).refresh();
      await ref.read(songsProvider.notifier).refreshPlayCounts();

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data replaced successfully!'),
            backgroundColor: AppTokens.success,
          ),
        );

        // Show restart dialog after a brief delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showRestartDialog();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore backup: $e'),
            backgroundColor: AppTokens.danger,
          ),
        );
      }
    }
  }

  Future<void> _deleteBackup(BackupInfo backupInfo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup'),
        content:
            Text('Are you sure you want to delete ${backupInfo.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('DELETE', style: TextStyle(color: AppTokens.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await BackupService.instance.deleteBackup(backupInfo);
      await _loadBackups();

      if (mounted) {
        appSnack(context, 'Backup deleted');
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Failed to delete backup: $e');
      }
    }
  }

  Future<void> _exportBackup(BackupInfo backupInfo) async {
    try {
      final bytes = await backupInfo.file.readAsBytes();
      final result = await FilePicker.platform.saveFile(
        fileName: backupInfo.filename,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: bytes,
      );

      if (result != null) {
        if (mounted) {
          appSnack(context, 'Backup exported to: $result');
        }
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Failed to export backup: $e');
      }
    }
  }

  Future<void> _compareBackup(BackupInfo backupInfo) async {
    // Find previous backup (older)
    // _backups is sorted by number descending.
    final index = _backups.indexOf(backupInfo);
    if (index == -1 || index == _backups.length - 1) {
      if (mounted) {
        appSnack(context, 'No older backup to compare with.');
      }
      return;
    }

    final oldBackup = _backups[index + 1];

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Comparing backups...'),
            ],
          ),
        ),
      );
    }

    try {
      final diff = await BackupService.instance.compareBackups(
        oldBackup,
        backupInfo,
      );

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Comparison with #${oldBackup.number}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDiffRow('Songs', diff.songCountDiff),
                const Divider(),
                _buildDiffRow('Stats Rows', diff.statsRowsDiff),
                const Divider(),
                _buildDiffRow('Size', diff.sizeBytesDiff, isBytes: true),
                if (diff.sizeBytesDiff > 0) ...[
                  const Divider(),
                  ListTile(
                    title: const Text('Data Added'),
                    trailing: Text(
                      _formatBytes(diff.sizeBytesDiff),
                      style: const TextStyle(
                          color: AppTokens.success,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        appSnack(context, 'Error comparing backups: $e');
      }
    }
  }

  Widget _buildDiffRow(String label, int diff, {bool isBytes = false}) {
    String diffText;
    Color color;

    if (diff > 0) {
      diffText = '+${isBytes ? _formatBytes(diff) : diff}';
      color = AppTokens.success;
    } else if (diff < 0) {
      diffText = '${isBytes ? _formatBytes(diff) : diff}';
      color = AppTokens.danger;
    } else {
      diffText = 'No change';
      color = AppTokens.fgTertiary;
    }

    return ListTile(
      title: Text(label),
      trailing: Text(
        diffText,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatBytes(int bytes) {
    final absBytes = bytes.abs();
    if (absBytes < 1024) {
      return '$bytes B';
    }
    if (absBytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Management'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isCreatingBackup ? null : _createBackup,
                          icon: _isCreatingBackup
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.backup_rounded),
                          label: Text(_isCreatingBackup
                              ? 'Creating...'
                              : 'Create Backup'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _backups.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            return _buildBackupCard(backup);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.backup_outlined,
            size: 64,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No backups yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first backup to protect your data',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard(BackupInfo backup) {
    return AppSurface(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '#${backup.number}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(backup.displayName),
        subtitle: Text('Size: ${backup.formattedSize}'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'restore':
                _restoreBackup(backup);
                break;
              case 'export':
                _exportBackup(backup);
                break;
              case 'compare':
                _compareBackup(backup);
                break;
              case 'delete':
                _deleteBackup(backup);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore_rounded),
                  SizedBox(width: 8),
                  Text('Restore'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_upload_rounded),
                  SizedBox(width: 8),
                  Text('Export'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'compare',
              child: Row(
                children: [
                  Icon(Icons.compare_arrows_rounded),
                  SizedBox(width: 8),
                  Text('Compare'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, color: AppTokens.danger),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppTokens.danger)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestartDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt, color: AppTokens.info, size: 48),
        title: const Text('Restart Required'),
        content: const Text(
          'Backup restore has been completed successfully.\n\n'
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
}



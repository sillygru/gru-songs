import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/backup_service.dart';
import '../../providers/auth_provider.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading backups: $e')),
        );
      }
    }
  }

  Future<void> _createBackup() async {
    final authState = ref.read(authProvider);
    final username = authState.username;
    if (username == null) return;

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final backupFilename =
          await BackupService.instance.createBackup(username);
      await _loadBackups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created: $backupFilename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create backup: $e')),
        );
      }
    } finally {
      setState(() {
        _isCreatingBackup = false;
      });
    }
  }

  Future<void> _restoreBackup(BackupInfo backupInfo) async {
    final authState = ref.read(authProvider);
    final username = authState.username;
    if (username == null) return;

    // Show confirmation dialog
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
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            const Text('• All your current statistics and play history'),
            const Text('• All your favorites and playlists'),
            const Text('• All your hidden songs and preferences'),
            const Text('• All your current settings and state'),
            const SizedBox(height: 12),
            const Text(
              'YOUR CURRENT DATA WILL BE PERMANENTLY LOST!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('YES, REPLACE EVERYTHING'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Replacing all data...'),
            ],
          ),
        ),
      );
    }

    try {
      await BackupService.instance.restoreFromBackup(username, backupInfo);

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data replaced successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back to refresh data
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore backup: $e'),
            backgroundColor: Colors.red,
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
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await BackupService.instance.deleteBackup(backupInfo);
      await _loadBackups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete backup: $e')),
        );
      }
    }
  }

  Future<void> _exportBackup(BackupInfo backupInfo) async {
    try {
      final result = await FilePicker.platform.saveFile(
        fileName: backupInfo.filename,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null) {
        await BackupService.instance.exportBackup(backupInfo, result);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup exported to: $result')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export backup: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Management'),
        centerTitle: true,
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
    return Card(
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
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

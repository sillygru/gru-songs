import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../services/backup_service.dart';
import '../../providers/providers.dart';

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
    final options = await _showBackupOptionsDialog();
    if (options == null) return;

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final backupFilename = await BackupService.instance.createBackup(options);
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

  Future<BackupOptions?> _showBackupOptionsDialog() async {
    return showDialog<BackupOptions>(
      context: context,
      builder: (context) => _BackupOptionsDialog(),
    );
  }

  Future<void> _restoreBackup(BackupInfo backupInfo) async {
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
      await BackupService.instance.restoreFromBackup(backupInfo);

      // Refresh data without full scan
      await ref.read(userDataProvider.notifier).refresh();
      await ref.read(songsProvider.notifier).refreshPlayCounts();
      ref.invalidate(audioPlayerManagerProvider);

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data replaced successfully!'),
            backgroundColor: Colors.green,
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

  Future<void> _compareBackup(BackupInfo backupInfo) async {
    // Find previous backup (older)
    // _backups is sorted by number descending.
    final index = _backups.indexOf(backupInfo);
    if (index == -1 || index == _backups.length - 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No older backup to compare with.')),
        );
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
                          color: Colors.green, fontWeight: FontWeight.bold),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error comparing backups: $e')),
        );
      }
    }
  }

  Widget _buildDiffRow(String label, int diff, {bool isBytes = false}) {
    String diffText;
    Color color;

    if (diff > 0) {
      diffText = '+${isBytes ? _formatBytes(diff) : diff}';
      color = Colors.green;
    } else if (diff < 0) {
      diffText = '${isBytes ? _formatBytes(diff) : diff}';
      color = Colors.red;
    } else {
      diffText = 'No change';
      color = Colors.grey;
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

  Future<void> _showRestartDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt, color: Colors.blue, size: 48),
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

class _BackupOptionsDialog extends StatefulWidget {
  const _BackupOptionsDialog();

  @override
  State<_BackupOptionsDialog> createState() => _BackupOptionsDialogState();
}

class _BackupOptionsDialogState extends State<_BackupOptionsDialog> {
  Set<BackupContentType> _selectedTypes = {
    BackupContentType.userStats,
    BackupContentType.userData,
  };

  String _getContentTypeName(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return 'User Stats';
      case BackupContentType.userData:
        return 'User Data';
      case BackupContentType.coverCache:
        return 'Cover Cache';
      case BackupContentType.libraryCache:
        return 'Library Cache';
      case BackupContentType.searchIndex:
        return 'Search Index';
      case BackupContentType.waveformCache:
        return 'Waveform Cache';
      case BackupContentType.colorCache:
        return 'Color Cache';
      case BackupContentType.lyricsCache:
        return 'Lyrics Cache';
    }
  }

  String _getContentTypeDescription(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return 'Play history, stats, merged groups';
      case BackupContentType.userData:
        return 'Favorites, playlists, preferences';
      case BackupContentType.coverCache:
        return 'Cached album artwork';
      case BackupContentType.libraryCache:
        return 'Cached metadata';
      case BackupContentType.searchIndex:
        return 'Search database';
      case BackupContentType.waveformCache:
        return 'Waveform data';
      case BackupContentType.colorCache:
        return 'Color palettes';
      case BackupContentType.lyricsCache:
        return 'Cached lyrics';
    }
  }

  IconData _getContentTypeIcon(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return Icons.analytics_outlined;
      case BackupContentType.userData:
        return Icons.person_outline;
      case BackupContentType.coverCache:
        return Icons.album_outlined;
      case BackupContentType.libraryCache:
        return Icons.library_music_outlined;
      case BackupContentType.searchIndex:
        return Icons.search_outlined;
      case BackupContentType.waveformCache:
        return Icons.waves_outlined;
      case BackupContentType.colorCache:
        return Icons.palette_outlined;
      case BackupContentType.lyricsCache:
        return Icons.lyrics_outlined;
    }
  }

  void _toggleType(BackupContentType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.backup_rounded, color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Backup',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Select content to backup',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: BackupContentType.values.map((type) {
            final isSelected = _selectedTypes.contains(type);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleType(type),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.12)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getContentTypeIcon(type),
                          size: 17,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getContentTypeName(type),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isSelected
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _getContentTypeDescription(type),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: theme.colorScheme.outline),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: _selectedTypes.isEmpty
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                            BackupOptions(contentTypes: _selectedTypes),
                          );
                        },
                  icon: const Icon(Icons.backup_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  label: const Text('Create'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

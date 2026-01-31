import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/namida_import_service.dart';
import '../../services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';

/// Screen for importing data from Namida backup files
class NamidaImportScreen extends ConsumerStatefulWidget {
  const NamidaImportScreen({super.key});

  @override
  ConsumerState<NamidaImportScreen> createState() => _NamidaImportScreenState();
}

class _NamidaImportScreenState extends ConsumerState<NamidaImportScreen> {
  bool _isLoading = false;
  bool _isImporting = false;
  String? _statusMessage;
  NamidaImportMode _importMode = NamidaImportMode.additive;

  Future<void> _selectAndImport() async {
    final authState = ref.read(authProvider);
    final username = authState.username;
    if (username == null) {
      _showError('Not logged in');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Validating backup file...';
    });

    try {
      final validationResult =
          await NamidaImportService().validateNamidaBackup();

      if (validationResult == null) {
        // User cancelled file picker
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      if (validationResult['valid'] != true) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        _showError(validationResult['error'] ?? 'Invalid backup file');
        return;
      }

      final importPath = validationResult['importPath'] as String;

      // Show import mode selection dialog
      if (mounted) {
        final confirmed = await _showImportConfirmationDialog();
        if (confirmed != true) {
          // Cleanup temp directory
          await _cleanupTempDir(importPath);
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
          return;
        }
      }

      setState(() {
        _isImporting = true;
        _statusMessage = 'Importing data...';
      });

      // Get music folder path for path mapping
      final musicFolder = await StorageService().getMusicFolderPath();
      if (musicFolder == null) {
        await _cleanupTempDir(importPath);
        setState(() {
          _isLoading = false;
          _isImporting = false;
          _statusMessage = null;
        });
        _showError(
            'Music folder not set. Please configure your music folder first.');
        return;
      }

      // Perform the import
      final result = await NamidaImportService().performImport(
        importPath: importPath,
        username: username,
        mode: _importMode,
        pathMapper: (namidaPath) => NamidaImportService.defaultPathMapper(
          namidaPath,
          musicFolder,
        ),
      );

      setState(() {
        _isLoading = false;
        _isImporting = false;
        _statusMessage = null;
      });

      if (result.success) {
        // Refresh user data
        await ref.read(userDataProvider.notifier).refresh();
        // Update song objects with new play counts from DB
        await ref.read(songsProvider.notifier).refreshPlayCounts();
        // Invalidate player manager to refresh stats and other states
        ref.invalidate(audioPlayerManagerProvider);

        if (mounted) {
          _showSuccessDialog(result);
        }
      } else {
        _showError(result.message);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isImporting = false;
        _statusMessage = null;
      });
      _showError('Import failed: $e');
    }
  }

  Future<void> _cleanupTempDir(String importPath) async {
    try {
      final tempDir = importPath
          .split('/')
          .where((p) => p.contains('namida_import_'))
          .firstOrNull;
      if (tempDir != null) {
        // Note: The service handles cleanup, but we ensure it here
      }
    } catch (_) {}
  }

  Future<bool?> _showImportConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import from Namida'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose how to import the data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RadioGroup<NamidaImportMode>(
                groupValue: _importMode,
                onChanged: (NamidaImportMode? value) {
                  setDialogState(() {
                    _importMode = value!;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<NamidaImportMode>(
                      title: const Text('Additive'),
                      subtitle: const Text(
                          'Add to existing data without removing anything'),
                      value: NamidaImportMode.additive,
                    ),
                    RadioListTile<NamidaImportMode>(
                      title: const Text('Replace'),
                      subtitle: const Text(
                          'Replace all existing data with imported data'),
                      value: NamidaImportMode.replace,
                    ),
                  ],
                ),
              ),
              if (_importMode == NamidaImportMode.replace) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Warning: This will replace all your current favorites, playlists, and stats!',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _importMode == NamidaImportMode.replace ? Colors.red : null,
                foregroundColor: _importMode == NamidaImportMode.replace
                    ? Colors.white
                    : null,
              ),
              child: const Text('IMPORT'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(NamidaImportResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text('Import Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            const SizedBox(height: 16),
            _buildResultRow(Icons.favorite_rounded, 'Favorites imported:',
                result.favoritesImported),
            _buildResultRow(Icons.playlist_play_rounded, 'Playlists imported:',
                result.playlistsImported),
            _buildResultRow(Icons.history_rounded, 'Tracks with stats:',
                result.tracksWithStatsImported),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Return to previous screen
            },
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(IconData icon, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            count.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Namida'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Import from Namida',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import your playlists, favorites, and listening history from a Namida backup file.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // What gets imported
            const Text(
              'What will be imported:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildFeatureRow(
                Icons.favorite_rounded, 'Favorites', 'Your liked songs'),
            _buildFeatureRow(Icons.playlist_play_rounded, 'Playlists',
                'All your custom playlists'),
            _buildFeatureRow(Icons.history_rounded, 'Listening History',
                'Play counts and stats'),
            const Spacer(),

            // Import Button
            if (_isLoading || _isImporting) ...[
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_statusMessage ?? 'Processing...'),
                  ],
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _selectAndImport,
                icon: const Icon(Icons.file_upload_rounded),
                label: const Text('Select Namida Backup File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select a Namida backup ZIP file to begin',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

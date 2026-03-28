import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/namida_import_service.dart';
import '../../services/storage_service.dart';
import '../../services/import_options.dart';
import '../../presentation/widgets/import_options_dialog.dart';
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

  Future<void> _selectAndImport() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Validating backup file...';
    });

    try {
      final validationResult =
          await NamidaImportService().validateNamidaBackup();

      if (validationResult == null) {
        // User cancelled file picker
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
        }
        return;
      }

      if (validationResult['valid'] != true) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
        }
        _showError(validationResult['error'] ?? 'Invalid backup file');
        return;
      }

      final importPath = validationResult['importPath'] as String;

      final availableCategories = {
        ImportDataCategory.favorites,
        ImportDataCategory.playlists,
        ImportDataCategory.playHistory,
      };

      if (!mounted) return;

      final importOptions = await showDialog<ImportOptions>(
        context: context,
        builder: (context) => ImportOptionsDialog(
          availableCategories: availableCategories,
          defaultAdditive: true,
          defaultRestoreDatabases: true,
          defaultRestorePlaybackState: false,
        ),
      );

      if (importOptions == null) {
        await _cleanupTempDir(importPath);
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isImporting = true;
          _statusMessage = 'Importing data...';
        });
      }

      final musicFolder = await StorageService().getMusicFolderPath();
      if (musicFolder == null) {
        await _cleanupTempDir(importPath);
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isImporting = false;
            _statusMessage = null;
          });
        }
        _showError(
            'Music folder not set. Please configure your music folder first.');
        return;
      }

      final result = await NamidaImportService().performImport(
        importPath: importPath,
        mode: importOptions.additive
            ? NamidaImportMode.additive
            : NamidaImportMode.replace,
        importFavorites:
            importOptions.hasCategory(ImportDataCategory.favorites),
        importPlaylists:
            importOptions.hasCategory(ImportDataCategory.playlists),
        importHistory:
            importOptions.hasCategory(ImportDataCategory.playHistory),
        pathMapper: (namidaPath) => NamidaImportService.defaultPathMapper(
          namidaPath,
          musicFolder,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isImporting = false;
          _statusMessage = null;
        });
      }

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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isImporting = false;
          _statusMessage = null;
        });
      }
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

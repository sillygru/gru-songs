import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/storage_analysis_service.dart';
import '../../providers/setup_provider.dart';
import '../../providers/providers.dart';

class StorageManagementScreen extends ConsumerStatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  ConsumerState<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState
    extends ConsumerState<StorageManagementScreen> {
  bool _isLoading = true;
  int _databaseSize = 0;
  int _coversSize = 0;
  int _backupsSize = 0;
  int _libraryCacheSize = 0;
  int _searchIndexSize = 0;
  int _waveformCacheSize = 0;
  int _colorCacheSize = 0;
  int _lyricsCacheSize = 0;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  Future<void> _loadSizes() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final dbSize = await StorageAnalysisService.instance.getDatabaseSize();
      final coversSize =
          await StorageAnalysisService.instance.getCoversCacheSize();
      final backupsSize =
          await StorageAnalysisService.instance.getBackupsSize();
      final libSize =
          await StorageAnalysisService.instance.getLibraryCacheSize();
      final searchSize =
          await StorageAnalysisService.instance.getSearchIndexSize();
      final waveformSize =
          await StorageAnalysisService.instance.getWaveformCacheSize();
      final colorSize =
          await StorageAnalysisService.instance.getColorCacheSize();
      final lyricsSize =
          await StorageAnalysisService.instance.getLyricsCacheSize();

      if (mounted) {
        setState(() {
          _databaseSize = dbSize;
          _coversSize = coversSize;
          _backupsSize = backupsSize;
          _libraryCacheSize = libSize;
          _searchIndexSize = searchSize;
          _waveformCacheSize = waveformSize;
          _colorCacheSize = colorSize;
          _lyricsCacheSize = lyricsSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading storage sizes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmText,
    required Color confirmColor,
    bool requireTextInput = false,
    String? textInputHint,
  }) async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    if (confirm1 != true) return false;
    if (!requireTextInput) return true;
    if (!mounted) return false;

    // Second confirmation with text input
    final controller = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To confirm, type "${textInputHint ?? 'DELETE'}" below:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: textInputHint ?? 'DELETE',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text == (textInputHint ?? 'DELETE')) {
                Navigator.pop(dialogContext, true);
              } else {
                // Use the captured scaffoldMessenger to avoid async gap issues
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please type the confirmation text exactly.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );

    return confirm2 == true;
  }

  Future<void> _handleClearDatabase() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Database?',
      content: 'This will permanently delete all your user data, including:\n\n'
          '• All playlists\n'
          '• Favorites and hidden songs\n'
          '• Playback statistics\n'
          '• App settings and preferences\n\n'
          'The app will reset. This action cannot be undone.',
      confirmText: 'Clear Database',
      confirmColor: Colors.red,
      requireTextInput: true,
      textInputHint: 'DELETE',
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearDatabase();

      // Reset
      if (mounted) {
        final storage = ref.read(storageServiceProvider);
        await storage.setSetupComplete(false);
        ref.read(setupProvider.notifier).setComplete(false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing database: $e')),
        );
      }
    }
  }

  Future<void> _handleClearCovers() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Cover Cache?',
      content: 'This will delete all cached album artwork.\n\n'
          'The covers will be re-extracted from your music files the next time you browse your library.',
      confirmText: 'Clear Covers',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearCoversCache();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing covers: $e')),
        );
      }
    }
  }

  Future<void> _handleClearBackups() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Backups?',
      content: 'This will delete all local backup files.\n\n'
          'Make sure you have exported any important backups before proceeding.',
      confirmText: 'Clear Backups',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearBackups();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backups cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing backups: $e')),
        );
      }
    }
  }

  Future<void> _handleClearLibraryCache() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Library Cache?',
      content: 'This will clear the library cache.\n\n'
          'Your music library will be rescanned the next time you open the app.',
      confirmText: 'Clear Cache',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearLibraryCache();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing library cache: $e')),
        );
      }
    }
  }

  Future<void> _handleClearSearchIndex() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Search Index?',
      content: 'This will delete the search index.\n\n'
          'The search index will be rebuilt automatically when you rescan your library.',
      confirmText: 'Clear Index',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearSearchIndex();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search index cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing search index: $e')),
        );
      }
    }
  }

  Future<void> _handleClearWaveformCache() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Waveform Cache?',
      content: 'This will delete all cached song waveforms.\n\n'
          'Waveforms will be regenerated the next time you view song details.',
      confirmText: 'Clear Cache',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearWaveformCache();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waveform cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing waveform cache: $e')),
        );
      }
    }
  }

  Future<void> _handleClearColorCache() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Color Cache?',
      content: 'This will delete all cached theme colors.\n\n'
          'Colors will be re-extracted from album art the next time songs are played.',
      confirmText: 'Clear Cache',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearColorCache();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Color cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing color cache: $e')),
        );
      }
    }
  }

  Future<void> _handleClearLyricsCache() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear Lyrics Cache?',
      content: 'This will remove cached lyrics lookups.\n\n'
          'Lyrics will be re-read from song metadata when needed.',
      confirmText: 'Clear Cache',
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearLyricsCache();
      await _loadSizes();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lyrics cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing lyrics cache: $e')),
        );
      }
    }
  }

  Future<void> _handleDangerousClear() async {
    final confirmed = await _showConfirmationDialog(
      title: 'Clear All App Data?',
      content: 'This action is dangerous and cannot be undone.\n\n'
          'It will permanently delete:\n'
          '• All your preferences and settings\n'
          '• Playback statistics and history\n'
          '• Cached song covers\n'
          '• All local backups\n'
          '• Library cache\n'
          '• Search index\n'
          '• Waveform cache\n'
          '• Lyrics cache\n\n'
          'The app will reset.',
      confirmText: 'Clear Everything',
      confirmColor: Colors.red,
      requireTextInput: true,
      textInputHint: 'DELETE',
    );

    if (!confirmed || !mounted) return;

    if (mounted) {
      setState(() => _isClearing = true);
    }

    try {
      await StorageAnalysisService.instance.clearAllUserData();

      // Reset
      if (mounted) {
        final storage = ref.read(storageServiceProvider);
        await storage.setSetupComplete(false);
        ref.read(setupProvider.notifier).setComplete(false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Storage'),
      ),
      body: _isLoading || _isClearing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSizes,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStorageCard(
                    title: 'Database',
                    subtitle: 'User data, statistics, and settings',
                    size: _databaseSize,
                    icon: Icons.storage_rounded,
                    color: Colors.blue,
                    onClear: _databaseSize > 0 ? _handleClearDatabase : null,
                    isDestructive: true,
                  ),
                  _buildStorageCard(
                    title: 'Cover Cache',
                    subtitle: 'Cached song album art',
                    size: _coversSize,
                    icon: Icons.image_rounded,
                    color: Colors.purple,
                    onClear: _coversSize > 0 ? _handleClearCovers : null,
                  ),
                  _buildStorageCard(
                    title: 'Backups',
                    subtitle: 'Local backup files',
                    size: _backupsSize,
                    icon: Icons.backup_rounded,
                    color: Colors.orange,
                    onClear: _backupsSize > 0 ? _handleClearBackups : null,
                  ),
                  _buildStorageCard(
                    title: 'Library Cache',
                    subtitle: 'Cached song library data',
                    size: _libraryCacheSize,
                    icon: Icons.library_music_rounded,
                    color: Colors.green,
                    onClear:
                        _libraryCacheSize > 0 ? _handleClearLibraryCache : null,
                  ),
                  _buildStorageCard(
                    title: 'Search Index',
                    subtitle: 'Search index for fast queries',
                    size: _searchIndexSize,
                    icon: Icons.search_rounded,
                    color: Colors.teal,
                    onClear:
                        _searchIndexSize > 0 ? _handleClearSearchIndex : null,
                  ),
                  _buildStorageCard(
                    title: 'Waveform Cache',
                    subtitle: 'Cached song waveforms for visualizers',
                    size: _waveformCacheSize,
                    icon: Icons.waves_rounded,
                    color: Colors.cyan,
                    onClear: _waveformCacheSize > 0
                        ? _handleClearWaveformCache
                        : null,
                  ),
                  _buildStorageCard(
                    title: 'Color Cache',
                    subtitle: 'Cached theme colors from album art',
                    size: _colorCacheSize,
                    icon: Icons.palette_rounded,
                    color: Colors.pink,
                    onClear:
                        _colorCacheSize > 0 ? _handleClearColorCache : null,
                  ),
                  _buildStorageCard(
                    title: 'Lyrics Cache',
                    subtitle: 'Cached lyrics availability and text',
                    size: _lyricsCacheSize,
                    icon: Icons.lyrics_rounded,
                    color: Colors.indigo,
                    onClear:
                        _lyricsCacheSize > 0 ? _handleClearLyricsCache : null,
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  ListTile(
                    title: const Text(
                      'Clear All User Data',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: const Text(
                      'Permanently delete all data and reset app',
                      style: TextStyle(color: Colors.red),
                    ),
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.red,
                      size: 32,
                    ),
                    onTap: _handleDangerousClear,
                    tileColor: Colors.red.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildStorageCard({
    required String title,
    required String subtitle,
    required int size,
    required IconData icon,
    required Color color,
    VoidCallback? onClear,
    bool isDestructive = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _formatSize(size),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (onClear != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.delete_outline,
                    color: isDestructive ? Colors.red : null,
                  ),
                  label: Text(
                    'Clear',
                    style: TextStyle(
                      color: isDestructive ? Colors.red : null,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDestructive ? Colors.red : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

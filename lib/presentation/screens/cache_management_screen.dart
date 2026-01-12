import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../services/cache_service.dart';

class CacheManagementScreen extends StatefulWidget {
  const CacheManagementScreen({super.key});

  @override
  State<CacheManagementScreen> createState() => _CacheManagementScreenState();
}

class _CacheManagementScreenState extends State<CacheManagementScreen> {
  String _audioCacheSize = "Calculating...";
  String _imageCacheSize = "Calculating...";
  String _otherCacheSize = "Calculating...";
  String _totalCacheSize = "Calculating...";

  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _calculateSizes();
  }

  Future<void> _calculateSizes() async {
    if (!mounted) return;
    
    try {
      final tempDir = await getTemporaryDirectory();
      
      final audioDir = Directory('${tempDir.path}/${CacheService.keyAudio}');
      final imageDir = Directory('${tempDir.path}/${CacheService.keyImages}');
      // Default cache manager and legacy image cache
      final defaultDir = Directory('${tempDir.path}/libCacheManager'); 
      final legacyImageDir = Directory('${tempDir.path}/libCachedImageData');

      int audioSize = await _getDirSize(audioDir);
      int imageSize = await _getDirSize(imageDir);
      int otherSize = await _getDirSize(defaultDir) + await _getDirSize(legacyImageDir);
      
      // Also check for any other large folders in temp? 
      // For now, let's stick to known keys.
      
      if (mounted) {
        setState(() {
          _audioCacheSize = _formatSize(audioSize);
          _imageCacheSize = _formatSize(imageSize);
          _otherCacheSize = _formatSize(otherSize);
          _totalCacheSize = _formatSize(audioSize + imageSize + otherSize);
        });
      }
    } catch (e) {
      debugPrint("Error calculating cache size: $e");
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    try {
      await for (var file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
    } catch (e) {
      debugPrint("Error getting dir size for ${dir.path}: $e");
    }
    return totalSize;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> _clearAudioCache() async {
    await _performClear(() async {
      await CacheService.audioCache.emptyCache();
    });
  }

  Future<void> _clearImageCache() async {
    await _performClear(() async {
      await CacheService.imageCache.emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  Future<void> _clearOtherCache() async {
    await _performClear(() async {
      await DefaultCacheManager().emptyCache();
      final tempDir = await getTemporaryDirectory();
      final legacyDir = Directory('${tempDir.path}/libCachedImageData');
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
    });
  }

  Future<void> _clearAll() async {
    await _performClear(() async {
      await CacheService.audioCache.emptyCache();
      await CacheService.imageCache.emptyCache();
      await DefaultCacheManager().emptyCache();
      
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final tempDir = await getTemporaryDirectory();
      final legacyDir = Directory('${tempDir.path}/libCachedImageData');
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
    });
  }

  Future<void> _performClear(Future<void> Function() action) async {
    if (_isClearing) return;
    setState(() => _isClearing = true);

    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cache cleared")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      await _calculateSizes();
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Storage & Cache"),
      ),
      body: _isClearing 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            _buildSectionTitle("Manage Storage"),
            _buildActionTile(
              title: "Clear Audio Cache",
              subtitle: "Frees up space from streamed songs",
              size: _audioCacheSize,
              icon: Icons.music_note,
              color: Colors.deepPurple,
              onTap: _clearAudioCache,
            ),
            _buildActionTile(
              title: "Clear Image Cache",
              subtitle: "Removes cached album covers",
              size: _imageCacheSize,
              icon: Icons.image,
              color: Colors.blue,
              onTap: _clearImageCache,
            ),
            if (_otherCacheSize != "0 B")
              _buildActionTile(
                title: "Clear Other Cache",
                subtitle: "Legacy or temporary files",
                size: _otherCacheSize,
                icon: Icons.cleaning_services,
                color: Colors.orange,
                onTap: _clearOtherCache,
              ),
            const Divider(height: 32),
             ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Clear All Cache", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: Text("Total: $_totalCacheSize"),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Clear All Cache?"),
                    content: const Text("This will delete all downloaded songs and images. They will need to be re-downloaded when played."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Clear All", style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  _clearAll();
                }
              },
            ),
          ],
        ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Total Cache Used", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(_totalCacheSize, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required String size,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("$subtitle • $size"),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/cache_service.dart';

class CacheManagementScreen extends StatefulWidget {
  const CacheManagementScreen({super.key});

  @override
  State<CacheManagementScreen> createState() => _CacheManagementScreenState();
}

class _CacheManagementScreenState extends State<CacheManagementScreen> {
  String _audioCacheSize = "Calculating...";
  String _imageCacheSize = "Calculating...";
  String _lyricsCacheSize = "Calculating...";
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
      int songsSize = await CacheService.instance.getCacheSize(category: 'songs');
      int imagesSize = await CacheService.instance.getCacheSize(category: 'images');
      int lyricsSize = await CacheService.instance.getCacheSize(category: 'lyrics');
      int totalV2 = await CacheService.instance.getCacheSize();
      
      final tempDir = await getTemporaryDirectory();
      final dirsToClear = ['audio_cache', 'image_cache', 'libCacheManager', 'libCachedImageData'];
      int oldSize = 0;
      for (var d in dirsToClear) {
        oldSize += await _getDirSize(Directory('${tempDir.path}/$d'));
      }
      
      if (mounted) {
        setState(() {
          _audioCacheSize = _formatSize(songsSize);
          _imageCacheSize = _formatSize(imagesSize);
          _lyricsCacheSize = _formatSize(lyricsSize);
          _otherCacheSize = _formatSize(oldSize);
          _totalCacheSize = _formatSize(totalV2 + oldSize);
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
        if (file is File) totalSize += await file.length();
      }
    } catch (_) {}
    return totalSize;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> _performClear(Future<void> Function() action) async {
    if (_isClearing) return;
    setState(() => _isClearing = true);

    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cache operations paused for 10s..."),
            duration: Duration(seconds: 3),
          )
        );
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

  void _showCategoryDetails(String category, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CacheCategoryDetailScreen(category: category, title: title),
      ),
    ).then((_) => _calculateSizes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Storage & Cache"),
      ),
      body: _isClearing 
        ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Clearing and pausing operations..."),
            ],
          ))
        : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            _buildSectionTitle("V2 Managed Cache"),
            _buildActionTile(
              title: "Audio Cache",
              subtitle: "Full song files",
              size: _audioCacheSize,
              icon: Icons.music_note,
              color: Colors.deepPurple,
              onTap: () => _showCategoryDetails('songs', 'Audio Cache'),
              onClear: () => _performClear(() => CacheService.instance.clearCache(category: 'songs')),
            ),
            _buildActionTile(
              title: "Image Cache",
              subtitle: "Album covers and thumbnails",
              size: _imageCacheSize,
              icon: Icons.image,
              color: Colors.blue,
              onTap: () => _showCategoryDetails('images', 'Image Cache'),
              onClear: () => _performClear(() => CacheService.instance.clearCache(category: 'images')),
            ),
            _buildActionTile(
              title: "Lyrics Cache",
              subtitle: "Synchronized lyric files",
              size: _lyricsCacheSize,
              icon: Icons.lyrics,
              color: Colors.teal,
              onTap: () => _showCategoryDetails('lyrics', 'Lyrics Cache'),
              onClear: () => _performClear(() => CacheService.instance.clearCache(category: 'lyrics')),
            ),
            const SizedBox(height: 16),
            _buildSectionTitle("Legacy & System"),
            _buildActionTile(
              title: "Other Cache",
              subtitle: "Temporary and legacy files",
              size: _otherCacheSize,
              icon: Icons.cleaning_services,
              color: Colors.orange,
              onTap: null,
              onClear: () => _performClear(() async {
                final tempDir = await getTemporaryDirectory();
                final dirs = ['audio_cache', 'image_cache', 'libCacheManager', 'libCachedImageData'];
                for (var d in dirs) {
                  final dir = Directory('${tempDir.path}/$d');
                  if (await dir.exists()) await dir.delete(recursive: true);
                }
              }),
            ),
            const Divider(height: 32),
             ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Clear Everything", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: Text("Total space: $_totalCacheSize"),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Reset All Cache?"),
                    content: const Text("This will delete all cached data and pause downloads for 10 seconds."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Clear All", style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  _performClear(() => CacheService.instance.clearCache());
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
            if (CacheService.instance.isPaused)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text("Downloads Paused", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
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
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required String size,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required VoidCallback onClear,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("$subtitle • $size"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onTap != null) const Icon(Icons.chevron_right, size: 20),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onClear,
              tooltip: "Clear this category",
            ),
          ],
        ),
      ),
    );
  }
}

class CacheCategoryDetailScreen extends StatefulWidget {
  final String category;
  final String title;

  const CacheCategoryDetailScreen({super.key, required this.category, required this.title});

  @override
  State<CacheCategoryDetailScreen> createState() => _CacheCategoryDetailScreenState();
}

class _CacheCategoryDetailScreenState extends State<CacheCategoryDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final entries = CacheService.instance.getEntries(widget.category);
    final sortedKeys = entries.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: sortedKeys.isEmpty
          ? const Center(child: Text("No items cached in this category"))
          : ListView.builder(
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                final key = sortedKeys[index];
                final entry = entries[key]!;
                return ListTile(
                  title: Text(key, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("Validated: ${entry.lastValidated.toString().split('.')[0]}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () async {
                      await CacheService.instance.removeEntry(widget.category, key);
                      setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}

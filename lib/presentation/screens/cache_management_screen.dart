import 'package:flutter/material.dart';
import '../../services/cache_service.dart';

class CacheManagementScreen extends StatefulWidget {
  const CacheManagementScreen({super.key});

  @override
  State<CacheManagementScreen> createState() => _CacheManagementScreenState();
}

class _CacheManagementScreenState extends State<CacheManagementScreen> {
  String _v3CacheSize = "Calculating...";
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _calculateSizes();
  }

  Future<void> _calculateSizes() async {
    if (!mounted) return;
    try {
      int v3Size = await CacheService.instance.getCacheSize();
      if (mounted) {
        setState(() {
          _v3CacheSize = _formatSize(v3Size);
        });
      }
    } catch (e) {
      debugPrint("Error calculating cache size: $e");
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> _performClear() async {
    if (_isClearing) return;
    setState(() => _isClearing = true);

    try {
      await CacheService.instance.clearCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
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
        title: const Text("Sync & Storage"),
      ),
      body: _isClearing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text("Sync Cache (V3)",
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Text(_v3CacheSize,
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text("Recalculate Size"),
                  onTap: _calculateSizes,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text("Clear Sync Cache",
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Clear Sync Cache?"),
                        content: const Text(
                            "This will only remove temporary sync files. Your local history and settings are preserved in the database."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel")),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Clear",
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _performClear();
                    }
                  },
                ),
              ],
            ),
    );
  }
}

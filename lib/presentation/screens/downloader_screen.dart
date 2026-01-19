import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../../services/storage_service.dart';

class DownloaderScreen extends ConsumerStatefulWidget {
  const DownloaderScreen({super.key});

  @override
  ConsumerState<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends ConsumerState<DownloaderScreen> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  bool _isDownloading = false;
  String? _statusMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();

    if (url.isEmpty || title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both URL and Title')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _statusMessage = 'Requesting download from server...';
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final storageService = StorageService();
      
      final musicPath = await storageService.getMusicFolderPath();
      if (musicPath == null) {
        throw Exception('Music library path not set');
      }

      final downloadedDir = Directory(p.join(musicPath, 'downloaded'));
      if (!await downloadedDir.exists()) {
        await downloadedDir.create(recursive: true);
      }

      // We'll update ApiService.downloadYoutube to return the response
      final response = await apiService.downloadYoutube(url, title);
      
      if (response.statusCode == 200) {
        setState(() {
          _statusMessage = 'Saving file...';
        });

        final filename = title.toLowerCase().endsWith('.m4a') ? title : '$title.m4a';
        final filePath = p.join(downloadedDir.path, filename);
        final file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          _isDownloading = false;
          _statusMessage = 'Download complete: $filename';
          _urlController.clear();
          _titleController.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded successfully to $filePath')),
          );
          // Trigger a scan of the library
          ref.read(songsProvider.notifier).refresh();
        }
      } else {
        throw Exception('Server error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Error: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Downloader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Download audio from YouTube via Server',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only "gru" has permission to use this tool. The file will be downloaded to your "downloaded" folder in the music library.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'YouTube URL',
                hintText: 'https://www.youtube.com/watch?v=...',
                border: OutlineInputBorder(),
              ),
              enabled: !_isDownloading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Song Title',
                hintText: 'Song Name (extension .m4a optional)',
                border: OutlineInputBorder(),
              ),
              enabled: !_isDownloading,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _startDownload,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isDownloading ? 'Downloading...' : 'Start Download'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage!.startsWith('Error')
                      ? Colors.red
                      : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

class AddSongsScreen extends ConsumerStatefulWidget {
  const AddSongsScreen({super.key});

  @override
  ConsumerState<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends ConsumerState<AddSongsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _youtubeUrlController = TextEditingController();
  final _youtubeFilenameController = TextEditingController();
  final _uploadFilenameController = TextEditingController();
  
  File? _selectedFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _youtubeUrlController.dispose();
    _youtubeFilenameController.dispose();
    _uploadFilenameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'flac', 'wav', 'alac'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        if (_uploadFilenameController.text.isEmpty) {
          _uploadFilenameController.text = result.files.single.name;
        }
      });
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null) return;

    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.uploadSong(_selectedFile!, _uploadFilenameController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful')));
        setState(() {
          _selectedFile = null;
          _uploadFilenameController.clear();
        });
        // Refresh song list
        ref.invalidate(songsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleYoutubeDownload() async {
    final url = _youtubeUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.downloadYoutube(url, _youtubeFilenameController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download started on server')));
        _youtubeUrlController.clear();
        _youtubeFilenameController.clear();
        // Refresh song list (might take a bit, so maybe wait or just invalidate)
        ref.invalidate(songsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Songs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.upload_file), text: 'Upload Local'),
            Tab(icon: Icon(Icons.link), text: 'YouTube Link'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUploadTab(),
                _buildYoutubeTab(),
              ],
            ),
    );
  }

  Widget _buildUploadTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_selectedFile != null) ...[
                  ListTile(
                    leading: const Icon(Icons.audio_file),
                    title: Text(_selectedFile!.path.split('/').last),
                    subtitle: const Text('Selected file'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _selectedFile = null),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _uploadFilenameController,
                    decoration: const InputDecoration(
                      labelText: 'Target Filename (optional)',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. MySong.mp3',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _handleUpload,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Upload to Server'),
                  ),
                ] else
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.add),
                      label: const Text('Select Music File'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Allowed formats: mp3, m4a, flac, wav, alac',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildYoutubeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _youtubeUrlController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube URL',
                    border: OutlineInputBorder(),
                    hintText: 'https://youtube.com/watch?v=...',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _youtubeFilenameController,
                  decoration: const InputDecoration(
                    labelText: 'Target Filename (optional)',
                    border: OutlineInputBorder(),
                    helperText: 'e.g. AwesomeSong.m4a',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _handleYoutubeDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download from YouTube'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'The server will download the audio using yt-dlp and save it to the music library.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

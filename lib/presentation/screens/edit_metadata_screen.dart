import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../providers/providers.dart';

class EditMetadataScreen extends ConsumerStatefulWidget {
  final Song song;

  const EditMetadataScreen({super.key, required this.song});

  @override
  ConsumerState<EditMetadataScreen> createState() => _EditMetadataScreenState();
}

class _EditMetadataScreenState extends ConsumerState<EditMetadataScreen> {
  late TextEditingController _filenameController;
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _filenameController = TextEditingController(
        text: p.basenameWithoutExtension(widget.song.filename));
    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    _albumController = TextEditingController(text: widget.song.album);
  }

  @override
  void dispose() {
    _filenameController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final newFilename = _filenameController.text.trim();
      final newTitle = _titleController.text.trim();
      final newArtist = _artistController.text.trim();
      final newAlbum = _albumController.text.trim();

      // 1. Handle Filename Rename if changed
      if (newFilename != p.basenameWithoutExtension(widget.song.filename)) {
        await ref
            .read(songsProvider.notifier)
            .renameSong(widget.song, newFilename);
      }

      // 2. Handle Metadata update
      if (newTitle != widget.song.title ||
          newArtist != widget.song.artist ||
          newAlbum != widget.song.album) {
        await ref
            .read(songsProvider.notifier)
            .updateSongMetadata(widget.song, newTitle, newArtist, newAlbum);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Metadata updated successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving metadata: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Metadata"),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text("SAVE", style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("File Information"),
            const SizedBox(height: 8),
            TextField(
              controller: _filenameController,
              decoration: const InputDecoration(
                labelText: "Filename (without extension)",
                border: OutlineInputBorder(),
                helperText: "Renaming the file will update it locally.",
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle("Song Metadata"),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: "Title",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: "Artist",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _albumController,
              decoration: const InputDecoration(
                labelText: "Album",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle("Additional Content"),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.lyrics_outlined),
              title: const Text("Edit Lyrics"),
              subtitle: Text(widget.song.lyricsUrl != null
                  ? "Lyrics file exists"
                  : "No lyrics file found"),
              trailing: const Icon(Icons.chevron_right),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade800),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LyricsEditorScreen(song: widget.song),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.2,
      ),
    );
  }
}

class LyricsEditorScreen extends ConsumerStatefulWidget {
  final Song song;

  const LyricsEditorScreen({super.key, required this.song});

  @override
  ConsumerState<LyricsEditorScreen> createState() => _LyricsEditorScreenState();
}

class _LyricsEditorScreenState extends ConsumerState<LyricsEditorScreen> {
  late TextEditingController _controller;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadLyrics();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    if (widget.song.lyricsUrl == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final repo = ref.read(songRepositoryProvider);
      final content = await repo.getLyrics(widget.song.lyricsUrl!);
      if (mounted) {
        setState(() {
          _controller.text = content ?? "";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading lyrics: $e")),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(songsProvider.notifier)
          .updateLyrics(widget.song, _controller.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lyrics saved")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving lyrics: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Lyrics"),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text("SAVE", style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    "Lyrics are saved as .lrc files. You can use [mm:ss.xx] timestamps for synced lyrics.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: "Enter lyrics here...",
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../widgets/album_art_image.dart';
import '../tokens/app_tokens.dart';
import '../components/app_feedback.dart';
import '../dialogs/lyrics_search_sheet.dart';

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

  Future<void> _pickImage(Song currentSong) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isSaving = true);
        final path = result.files.single.path!;
        await ref
            .read(songsProvider.notifier)
            .updateSongCover(currentSong, path);

        if (mounted) {
          appSnack(context, "Cover updated successfully");
        }
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, "Error picking image: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeImage(Song currentSong) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Cover"),
        content: const Text("Are you sure you want to remove the cover art?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("REMOVE")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      try {
        await ref
            .read(songsProvider.notifier)
            .updateSongCover(currentSong, null);
        if (mounted) {
          appSnack(context, "Cover removed");
        }
      } catch (e) {
        if (mounted) {
          appSnack(context, "Error removing cover: $e");
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _fixThumbnail(Song currentSong) async {
    if (currentSong.coverUrl == null) return;

    try {
      setState(() => _isSaving = true);

      final fixedOptions = await ref
          .read(fileManagerServiceProvider)
          .getFixedCoverOptions(currentSong);

      if (!mounted) return;

      // Show comparison dialog
      final resultBytes = await showDialog<Uint8List>(
        context: context,
        builder: (context) {
          int selectedIndex = 0;
          bool showAlternatives = false;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text("Fix Thumbnail Result"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Review the changes below:"),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text("Original",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: AppTokens.brSm,
                                child: Container(
                                  color: Colors
                                      .black12, // Subtle background to see borders
                                  child: Image.file(
                                    File(currentSong.coverUrl!),
                                    height: 100,
                                    width: 100,
                                    fit: BoxFit
                                        .contain, // Changed from cover to contain to show full image including borders
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                  fixedOptions.length > 1
                                      ? "New (Option ${selectedIndex + 1})"
                                      : "New",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: AppTokens.brSm,
                                child: Container(
                                  color: Colors.black12,
                                  child: Image.memory(
                                    fixedOptions[selectedIndex],
                                    height: 100,
                                    width: 100,
                                    fit: BoxFit.contain, // Consistent scaling
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (fixedOptions.length > 1) ...[
                      const SizedBox(height: 16),
                      if (!showAlternatives)
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => showAlternatives = true),
                          icon: const Icon(Icons.grid_view),
                          label: const Text("See Alternatives"),
                        )
                      else
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: fixedOptions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => selectedIndex = index),
                                child: Container(
                                  padding: const EdgeInsets.all(AppTokens.s1),
                                  decoration: BoxDecoration(
                                    color: index == selectedIndex
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.28)
                                        : Colors.transparent,
                                    borderRadius: AppTokens.brSm,
                                  ),
                                  child: Image.memory(
                                    fixedOptions[index],
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, fixedOptions[selectedIndex]),
                    child: const Text("Apply"),
                  ),
                ],
              );
            },
          );
        },
      );

      if (resultBytes != null) {
        // We need to save the bytes to a temp file to pass to updateSongCover
        // (Since updateSongCover expects a file path)
        final tempDir = await Directory.systemTemp.createTemp();
        final tempFile = File(p.join(tempDir.path, 'fixed_cover.jpg'));
        await tempFile.writeAsBytes(resultBytes);

        await ref
            .read(songsProvider.notifier)
            .updateSongCover(currentSong, tempFile.path);

        // Clean up temp file
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}

        if (mounted) {
          appSnack(context, "Thumbnail fixed successfully");
        }
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, "Error fixing thumbnail: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showFixHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.auto_fix_high),
            SizedBox(width: 8),
            Text("Fix Thumbnail"),
          ],
        ),
        content: const Text(
          "This tool automatically improves your album art by:\n\n"
          "1. Detecting and removing black bars/borders (common in YouTube thumbnails)\n"
          "2. Cropping the image to a perfect square (1:1 ratio)\n\n"
          "Best used for converting 16:9 thumbnails into proper album covers.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  Future<void> _exportImage(Song currentSong) async {
    if (currentSong.coverUrl == null) return;

    try {
      setState(() => _isSaving = true);

      // Get bytes first to satisfy file_picker requirement on Android/iOS
      final bytes = await ref
          .read(fileManagerServiceProvider)
          .getCoverExportBytes(currentSong);

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Cover',
        fileName:
            '${p.basenameWithoutExtension(currentSong.filename)}_cover.jpg',
        type: FileType.image,
        bytes: bytes, // Required for Android/iOS
      );

      if (savePath != null) {
        // On desktop, we need to write the file ourselves
        if (!Platform.isAndroid && !Platform.isIOS) {
          await File(savePath).writeAsBytes(bytes);
        }

        if (mounted) {
          appSnack(context, "Cover exported to $savePath");
        }
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, "Error exporting cover: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final newFilename = _filenameController.text.trim();
      final newTitle = _titleController.text.trim();
      final newArtist = _artistController.text.trim();
      final newAlbum = _albumController.text.trim();

      // 1. Handle Filename Rename if changed. The renamed song is carried
      //    forward: the metadata write below addresses the file by path, and
      //    the old one no longer exists.
      var song = widget.song;
      if (newFilename != p.basenameWithoutExtension(song.filename)) {
        song = await ref.read(songsProvider.notifier).renameSong(
              song,
              newFilename,
            );
      }

      // 2. Handle Metadata update
      if (newTitle != song.title ||
          newArtist != song.artist ||
          newAlbum != song.album) {
        await ref
            .read(songsProvider.notifier)
            .updateSongMetadata(song, newTitle, newArtist, newAlbum);
      }

      if (mounted) {
        Navigator.pop(context);
        appSnack(context, "Metadata updated successfully");
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, "Error saving metadata: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for updates to the song
    final songs = ref.watch(songsProvider).asData?.value ?? [];
    final currentSong = songs.firstWhere(
      (s) => s.filename == widget.song.filename,
      orElse: () => widget.song,
    );

    return AmbientScaffold(
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
            _buildSectionTitle("Cover Art"),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(
                  borderRadius: AppTokens.brSm,
                  child: AlbumArtImage(
                    url: currentSong.coverUrl ?? '',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _pickImage(currentSong),
                        icon: const Icon(Icons.image_rounded),
                        label: const Text("Change Cover"),
                        style: AppTokens.tonalButton,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: currentSong.coverUrl == null
                                  ? null
                                  : () => _fixThumbnail(currentSong),
                              icon: const Icon(Icons.auto_fix_high_rounded),
                              label: const Text("Fix Thumbnail"),
                              style: AppTokens.tonalButton,
                            ),
                          ),
                          IconButton(
                            onPressed: _showFixHelp,
                            icon: const Icon(Icons.help_outline_rounded),
                            tooltip: "What does this do?",
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: currentSong.coverUrl == null
                                  ? null
                                  : () => _exportImage(currentSong),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text("Export"),
                              style: AppTokens.tonalButton,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: currentSong.coverUrl == null
                                  ? null
                                  : () => _removeImage(currentSong),
                              icon: const Icon(Icons.delete_rounded),
                              label: const Text("Remove"),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTokens.surface(2),
                                foregroundColor: AppTokens.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
              subtitle: const Text("View or edit embedded lyrics"),
              trailing: const Icon(Icons.chevron_right),
              shape: RoundedRectangleBorder(
                borderRadius: AppTokens.brSm,
                side: BorderSide(color: AppTokens.fgTertiary),
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
    try {
      final repo = ref.read(songRepositoryProvider);
      final songs = ref.read(songsProvider).asData?.value ?? const <Song>[];
      final currentSong = songs.firstWhere(
        (s) => s.filename == widget.song.filename,
        orElse: () => widget.song,
      );
      final content = await repo.getLyrics(currentSong);
      if (mounted) {
        setState(() {
          _controller.text = content ?? "";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        appSnack(context, "Error loading lyrics: $e");
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
        appSnack(context, "Lyrics saved");
      }
    } catch (e) {
      if (mounted) {
        appSnack(context, "Error saving lyrics: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Drops a lyrics sheet from LRCLIB into the editor without saving, so it can
  /// be corrected or retimed before it touches the file.
  Future<void> _searchOnline() async {
    final chosen = await showLyricsSearchSheet(context, song: widget.song);
    if (chosen == null || !mounted) return;

    setState(() => _controller.text = chosen);
    appSnack(context, "Lyrics loaded — press SAVE to apply");
  }

  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      appBar: AppBar(
        title: const Text("Edit Lyrics"),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore_rounded),
            tooltip: "Search online",
            onPressed: _isSaving ? null : _searchOnline,
          ),
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
                    "Lyrics are embedded in the audio file. You can use [mm:ss.xx] timestamps for synced lyrics.",
                    style: TextStyle(fontSize: 12, color: AppTokens.fgTertiary),
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

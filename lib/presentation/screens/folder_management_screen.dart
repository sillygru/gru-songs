import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/android_storage_service.dart';
import '../../providers/providers.dart';
import 'package:file_picker/file_picker.dart';

class FolderManagementScreen extends ConsumerStatefulWidget {
  final bool isMusicFolders;

  const FolderManagementScreen({
    super.key,
    required this.isMusicFolders,
  });

  @override
  ConsumerState<FolderManagementScreen> createState() =>
      _FolderManagementScreenState();
}

class _FolderManagementScreenState
    extends ConsumerState<FolderManagementScreen> {
  List<Map<String, String>> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final storage = ref.read(storageServiceProvider);
    final folders = widget.isMusicFolders
        ? await storage.getMusicFolders()
        : await storage.getLyricsFolders();
    setState(() {
      _folders = folders;
      _isLoading = false;
    });
  }

  Future<void> _addFolder() async {
    if (Platform.isAndroid && !widget.isMusicFolders) {
      // For lyrics folders on Android, use SAF
      final selection = await AndroidStorageService.pickTree();
      if (selection == null) return;
      if (selection.path == null || selection.path!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unable to access selected folder")),
          );
        }
        return;
      }
      final storage = ref.read(storageServiceProvider);
      if (widget.isMusicFolders) {
        await storage.addMusicFolder(selection.path!, selection.treeUri);
      } else {
        await storage.addLyricsFolder(selection.path!, selection.treeUri);
      }
    } else {
      // For music folders or non-Android platforms, use file picker
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;
      final storage = ref.read(storageServiceProvider);
      if (widget.isMusicFolders) {
        await storage.addMusicFolder(selectedDirectory, null);
      } else {
        await storage.addLyricsFolder(selectedDirectory, null);
      }
    }

    await _loadFolders();
    ref.invalidate(songsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.isMusicFolders
                ? "Music folder added"
                : "Lyrics folder added")),
      );
    }
  }

  Future<void> _removeFolder(String path) async {
    final storage = ref.read(storageServiceProvider);
    if (widget.isMusicFolders) {
      await storage.removeMusicFolder(path);
    } else {
      await storage.removeLyricsFolder(path);
    }

    await _loadFolders();
    ref.invalidate(songsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.isMusicFolders
                ? "Music folder removed"
                : "Lyrics folder removed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isMusicFolders ? "Music Folders" : "Lyrics Folders";
    final subtitle = widget.isMusicFolders
        ? "Select folders containing your music files"
        : "Select folders containing .lrc or .txt lyric files";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: _folders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No folders added yet",
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final path = folder['path'] ?? '';
                            final name = path.split('/').last;

                            return ListTile(
                              leading: const Icon(Icons.folder),
                              title: Text(name),
                              subtitle: Text(
                                path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeFolder(path),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _addFolder,
                      icon: const Icon(Icons.add),
                      label: const Text("Add Folder"),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

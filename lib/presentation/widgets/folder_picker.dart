import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../../services/android_storage_service.dart';
import 'folder_grid_image.dart';

class FolderPicker extends ConsumerStatefulWidget {
  final String rootPath;
  final String? currentRelativePath;

  const FolderPicker({
    super.key,
    required this.rootPath,
    this.currentRelativePath,
  });

  @override
  ConsumerState<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<FolderPicker> {
  late String _currentRelativePath;

  @override
  void initState() {
    super.initState();
    _currentRelativePath = widget.currentRelativePath ?? '';
  }

  Future<String?> _showNewFolderDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _getMergedFolders(
      String path, List<String> songFolders) async {
    final Set<String> allFolders = {...songFolders};
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (var entity in entities) {
          if (entity is Directory) {
            allFolders.add(p.basename(entity.path));
          }
        }
      }
    } catch (e) {
      debugPrint("Error listing directory: $e");
    }
    return allFolders.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsyncValue = ref.watch(songsProvider);

    return AlertDialog(
      title: const Text('Select Destination Folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: songsAsyncValue.when(
          data: (allSongs) {
            final currentFullPath = _currentRelativePath.isEmpty
                ? widget.rootPath
                : p.join(widget.rootPath, _currentRelativePath);

            final content = LibraryLogic.getFolderContent(
              allSongs: allSongs,
              currentFullPath: currentFullPath,
            );

            return FutureBuilder<List<String>>(
              future: _getMergedFolders(currentFullPath, content.subFolders),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final sortedSubFolders = snapshot.data!;

                return Column(
                  children: [
                    Row(
                      children: [
                        if (_currentRelativePath.isNotEmpty)
                          Expanded(
                            child: ListTile(
                              leading: const Icon(Icons.arrow_back),
                              title: const Text('.. (Go back)'),
                              onTap: () {
                                setState(() {
                                  final parts = p.split(_currentRelativePath);
                                  if (parts.length <= 1) {
                                    _currentRelativePath = '';
                                  } else {
                                    _currentRelativePath = p.joinAll(
                                        parts.sublist(0, parts.length - 1));
                                  }
                                });
                              },
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          tooltip: 'New Folder',
                          onPressed: () async {
                            final name = await _showNewFolderDialog(context);
                            if (name != null && name.isNotEmpty) {
                              try {
                                final newFolderPath =
                                    _currentRelativePath.isEmpty
                                        ? p.join(widget.rootPath, name)
                                        : p.join(widget.rootPath,
                                            _currentRelativePath, name);

                                final newDir = Directory(newFolderPath);
                                if (!await newDir.exists()) {
                                  await newDir.create(recursive: true);
                                }

                                // Keep state in sync for scanner refresh.
                                await ref
                                    .read(songsProvider.notifier)
                                    .refresh();

                                setState(() {
                                  _currentRelativePath =
                                      _currentRelativePath.isEmpty
                                          ? name
                                          : p.join(_currentRelativePath, name);
                                });
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Error creating folder: $e')),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    Expanded(
                      child: sortedSubFolders.isEmpty
                          ? const Center(
                              child: Text(
                                  "Empty folder. You can select it below."))
                          : ListView.builder(
                              itemCount: sortedSubFolders.length,
                              itemBuilder: (context, index) {
                                final folderName = sortedSubFolders[index];
                                final folderSongs =
                                    content.subFolderSongs[folderName] ?? [];
                                return ListTile(
                                  leading: FolderGridImage(
                                      songs: folderSongs, size: 40),
                                  title: Text(folderName),
                                  onTap: () {
                                    setState(() {
                                      _currentRelativePath =
                                          _currentRelativePath.isEmpty
                                              ? folderName
                                              : p.join(_currentRelativePath,
                                                  folderName);
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Selected: ${_currentRelativePath.isEmpty ? "Root" : _currentRelativePath}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final targetPath = _currentRelativePath.isEmpty
                ? widget.rootPath
                : p.join(widget.rootPath, _currentRelativePath);
            Navigator.pop(context, targetPath);
          },
          child: const Text('Select This Folder'),
        ),
      ],
    );
  }
}

Future<String?> showFolderPicker(BuildContext context, String rootPath,
    {String? currentRelativePath}) {
  return showDialog<String>(
    context: context,
    builder: (context) => FolderPicker(
        rootPath: rootPath, currentRelativePath: currentRelativePath),
  );
}

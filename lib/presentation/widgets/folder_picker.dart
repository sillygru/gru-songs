import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../../services/library_logic.dart';

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

            final sortedSubFolders = content.subFolders;

            return Column(
              children: [
                if (_currentRelativePath.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('.. (Go back)'),
                    onTap: () {
                      setState(() {
                        final parts = p.split(_currentRelativePath);
                        if (parts.length <= 1) {
                          _currentRelativePath = '';
                        } else {
                          _currentRelativePath =
                              p.joinAll(parts.sublist(0, parts.length - 1));
                        }
                      });
                    },
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: sortedSubFolders.length,
                    itemBuilder: (context, index) {
                      final folderName = sortedSubFolders[index];
                      return ListTile(
                        leading: const Icon(Icons.folder, color: Colors.amber),
                        title: Text(folderName),
                        onTap: () {
                          setState(() {
                            _currentRelativePath = _currentRelativePath.isEmpty
                                ? folderName
                                : p.join(_currentRelativePath, folderName);
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

import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../components/app_feedback.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../tokens/app_tokens.dart';

class FolderManagementScreen extends ConsumerStatefulWidget {
  const FolderManagementScreen({super.key});

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
    final folders = await storage.getMusicFolders();
    setState(() {
      _folders = folders;
      _isLoading = false;
    });
  }

  Future<void> _addFolder() async {
    final storage = ref.read(storageServiceProvider);
    final selection = await storage.pickMusicFolder();
    if (selection == null || selection['path']!.isEmpty) {
      if (mounted) {
        appSnack(context, "Unable to access selected folder");
      }
      return;
    }
    await storage.addMusicFolder(
      selection['path']!,
      selection['treeUri'],
      iosBookmarkId: selection['iosBookmarkId'],
      platform: selection['platform'],
    );

    await _loadFolders();
    ref.invalidate(musicFoldersProvider);
    ref.invalidate(songsProvider);

    if (mounted) {
      appSnack(context, "Music folder added");
    }
  }

  Future<void> _removeFolder(Map<String, String> folder) async {
    final storage = ref.read(storageServiceProvider);
    await storage.removeMusicFolder(
      folder['path'] ?? '',
      iosBookmarkId: folder['iosBookmarkId'],
    );

    await _loadFolders();
    ref.invalidate(musicFoldersProvider);
    ref.invalidate(songsProvider);

    if (mounted) {
      appSnack(context, "Music folder removed");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Music Folders'),
      body: _isLoading
          ? const AppLoading()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5,
                    AppTokens.s3,
                    AppTokens.s5,
                    AppTokens.s3,
                  ),
                  child: Text(
                    'Select folders containing your music files',
                    style: AppTokens.rowSubtitle(context),
                  ),
                ),
                Expanded(
                  child: _folders.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.folder_open_rounded,
                          title: 'No folders added yet',
                          message: 'Add a folder to build your library.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s3,
                          ),
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final path = folder['path'] ?? '';
                            final name = path.split('/').last;

                            return AppListRow(
                              leading: AppRowIcon(
                                icon: Icons.folder_rounded,
                                color: AppTokens.accentOf(context, ref),
                              ),
                              title: name,
                              subtitle: path,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                tooltip: 'Remove folder',
                                onPressed: () => _removeFolder(folder),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _addFolder,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Folder'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

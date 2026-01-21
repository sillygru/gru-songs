import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import 'folder_picker.dart';

void showFolderOptionsMenu(BuildContext context, WidgetRef ref,
    String folderName, String folderRelativePath) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                folderName,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text("Move Folder"),
              onTap: () async {
                if (kDebugMode) {
                  debugPrint("UI: Move Folder tapped for $folderName");
                }
                Navigator.pop(sheetContext); // Close bottom sheet

                final storage = ref.read(storageServiceProvider);
                final rootPath = await storage.getMusicFolderPath();
                if (rootPath == null) {
                  if (kDebugMode) debugPrint("UI: ERROR - rootPath is null");
                  return;
                }

                if (context.mounted) {
                  if (kDebugMode) debugPrint("UI: Opening folder picker...");
                  final targetParentPath =
                      await showFolderPicker(context, rootPath);

                  if (targetParentPath != null) {
                    if (kDebugMode) {
                      debugPrint(
                          "UI: Selected target parent: $targetParentPath");
                    }
                    try {
                      final oldFolderPath =
                          p.join(rootPath, folderRelativePath);
                      if (kDebugMode) {
                        debugPrint("UI: Old folder full path: $oldFolderPath");
                      }

                      await ref
                          .read(songsProvider.notifier)
                          .moveFolder(oldFolderPath, targetParentPath);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  "Moved $folderName to $targetParentPath")),
                        );
                      }
                    } catch (e) {
                      if (kDebugMode) debugPrint("UI: ERROR during move: $e");
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error moving folder: $e")),
                        );
                      }
                    }
                  } else {
                    if (kDebugMode) debugPrint("UI: Folder picker cancelled");
                  }
                } else {
                  if (kDebugMode) {
                    debugPrint("UI: ERROR - context not mounted after pop");
                  }
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

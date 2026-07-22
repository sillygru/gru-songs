import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../providers/providers.dart';
import '../components/app_feedback.dart';
import '../components/app_sheet.dart';
import 'folder_picker.dart';

/// [folderFullPath] is the absolute path of the folder the row stands for — the
/// library tree is not always rooted at the first configured music folder, so a
/// relative path cannot be resolved reliably here.
void showFolderOptionsMenu(BuildContext context, WidgetRef ref,
    String folderName, String folderFullPath) {
  showAppSheet(
    context,
    title: folderName,
    builder: (sheetContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: Icons.drive_file_move_outlined,
            label: 'Move Folder',
            onTap: () async {
              if (kDebugMode) {
                debugPrint("UI: Move Folder tapped for $folderName");
              }
              Navigator.pop(sheetContext); // Close bottom sheet

              final storage = ref.read(storageServiceProvider);
              final rootPath = await storage.getMusicFolderPath() ??
                  p.dirname(folderFullPath);

              if (context.mounted) {
                if (kDebugMode) debugPrint("UI: Opening folder picker...");
                final targetParentPath =
                    await showFolderPicker(context, rootPath);

                if (targetParentPath != null) {
                  if (kDebugMode) {
                    debugPrint("UI: Selected target parent: $targetParentPath");
                  }
                  try {
                    if (kDebugMode) {
                      debugPrint("UI: Old folder full path: $folderFullPath");
                    }

                    await ref
                        .read(songsProvider.notifier)
                        .moveFolder(folderFullPath, targetParentPath);

                    if (context.mounted) {
                      appSnack(
                        context,
                        'Moved $folderName to $targetParentPath',
                        tone: AppTone.success,
                      );
                    }
                  } catch (e) {
                    if (kDebugMode) debugPrint("UI: ERROR during move: $e");
                    if (context.mounted) {
                      appSnack(context, 'Error moving folder: $e',
                          tone: AppTone.danger);
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
      );
    },
  );
}

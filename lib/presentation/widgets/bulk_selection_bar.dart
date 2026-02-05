import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../screens/bulk_metadata_screen.dart';
import '../screens/edit_metadata_screen.dart';

class BulkSelectionBar extends ConsumerWidget {
  const BulkSelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    if (!selectionState.isSelectionMode) return const SizedBox.shrink();

    final selectedCount = selectionState.selectedFilenames.length;
    final allSongs = ref.watch(songsProvider).value ?? [];
    final selectedSongs = allSongs
        .where((s) => selectionState.selectedFilenames.contains(s.filename))
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(selectionProvider.notifier).exitSelectionMode(),
                ),
                Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final allFilenames =
                        allSongs.map((s) => s.filename).toList();
                    ref
                        .read(selectionProvider.notifier)
                        .selectAll(allFilenames);
                  },
                  child: const Text('Select All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.edit,
                  label: 'Metadata',
                  onTap: selectedCount > 0
                      ? () {
                          if (selectedCount == 1) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditMetadataScreen(song: selectedSongs[0]),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    BulkMetadataScreen(songs: selectedSongs),
                              ),
                            );
                          }
                        }
                      : null,
                ),
                _ActionButton(
                  icon: Icons.visibility_off,
                  label: 'Hide',
                  onTap: selectedCount > 0
                      ? () => _confirmHide(context, ref, selectedSongs)
                      : null,
                ),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: Colors.redAccent,
                  onTap: selectedCount > 0
                      ? () => _confirmDelete(context, ref, selectedSongs)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmHide(BuildContext context, WidgetRef ref, List<Song> songs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hide Songs'),
        content: Text('Hide ${songs.length} selected songs from library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(userDataProvider.notifier).bulkHide(
                    songs.map((s) => s.filename).toList(),
                    true,
                  );
              ref.read(selectionProvider.notifier).exitSelectionMode();
              Navigator.pop(context);
            },
            child: const Text('Hide'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, List<Song> songs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Files'),
        content: Text(
          'Permanently delete ${songs.length} files from storage? This cannot be undone.',
          style: const TextStyle(color: Colors.redAccent),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              ref.read(songsProvider.notifier).bulkDeleteSongs(songs);
              ref.read(selectionProvider.notifier).exitSelectionMode();
              Navigator.pop(context);
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final isDisabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDisabled
                  ? effectiveColor.withValues(alpha: 0.3)
                  : effectiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDisabled
                    ? effectiveColor.withValues(alpha: 0.3)
                    : effectiveColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

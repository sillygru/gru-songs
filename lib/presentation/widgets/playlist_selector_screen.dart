import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

void showPlaylistSelector(
    BuildContext context, WidgetRef ref, String songFilename) {
  showDialog(
    context: context,
    builder: (context) => PlaylistSelectorDialog(songFilename: songFilename),
  );
}

class PlaylistSelectorDialog extends ConsumerStatefulWidget {
  final String songFilename;

  const PlaylistSelectorDialog({super.key, required this.songFilename});

  @override
  ConsumerState<PlaylistSelectorDialog> createState() =>
      _PlaylistSelectorDialogState();
}

class _PlaylistSelectorDialogState
    extends ConsumerState<PlaylistSelectorDialog> {
  late Set<String> _selectedPlaylistIds;
  late bool _isFavorite;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final userData = ref.read(userDataProvider);
      _isFavorite = userData.isFavorite(widget.songFilename);
      _selectedPlaylistIds = userData.playlists
          .where((pl) =>
              pl.songs.any((ps) => ps.songFilename == widget.songFilename))
          .map((pl) => pl.id)
          .toSet();
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final playlists = userData.playlists;

    return AlertDialog(
      title: const Text('Add to...'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New Playlist'),
                onTap: () {
                  _showNewPlaylistDialog(context, ref, widget.songFilename);
                },
              ),
              const Divider(),
              CheckboxListTile(
                title: const Text('Favorites'),
                secondary: const Icon(Icons.favorite, color: Colors.red),
                value: _isFavorite,
                onChanged: (val) {
                  setState(() => _isFavorite = val ?? false);
                },
              ),
              const Divider(),
              ...playlists.map((playlist) {
                final isSelected = _selectedPlaylistIds.contains(playlist.id);
                return CheckboxListTile(
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songs.length} songs'),
                  secondary: const Icon(Icons.queue_music),
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPlaylistIds.add(playlist.id);
                      } else {
                        _selectedPlaylistIds.remove(playlist.id);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final notifier = ref.read(userDataProvider.notifier);
            final currentData = ref.read(userDataProvider);

            // Handle Favorites
            if (_isFavorite != currentData.isFavorite(widget.songFilename)) {
              await notifier.toggleFavorite(widget.songFilename, sync: false);
            }

            // Handle Playlists
            for (final pl in playlists) {
              final wasIn =
                  pl.songs.any((ps) => ps.songFilename == widget.songFilename);
              final nowIn = _selectedPlaylistIds.contains(pl.id);

              if (nowIn && !wasIn) {
                await notifier.addSongToPlaylist(pl.id, widget.songFilename,
                    sync: false);
              } else if (!nowIn && wasIn) {
                await notifier.removeSongFromPlaylist(
                    pl.id, widget.songFilename,
                    sync: false);
              }
            }

            // Perform a single sync at the end
            await notifier.syncWithServer();

            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Updated selections')),
              );
            }
          },
          child: const Text('Done'),
        ),
      ],
    );
  }

  void _showNewPlaylistDialog(
      BuildContext context, WidgetRef ref, String songFilename) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Playlist Name'),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref
                  .read(userDataProvider.notifier)
                  .createPlaylist(value.trim(), songFilename);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Created playlist "$value"')),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(userDataProvider.notifier)
                    .createPlaylist(name, songFilename);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created playlist "$name"')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

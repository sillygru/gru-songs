import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

void showPlaylistSelector(
    BuildContext context, WidgetRef ref, String songFilename) {
  showDialog(
    context: context,
    builder: (context) => PlaylistSelectorDialog(songFilenames: [songFilename]),
  );
}

void showBulkPlaylistSelector(
    BuildContext context, WidgetRef ref, List<String> songFilenames) {
  showDialog(
    context: context,
    builder: (context) => PlaylistSelectorDialog(songFilenames: songFilenames),
  );
}

class PlaylistSelectorDialog extends ConsumerStatefulWidget {
  final List<String> songFilenames;

  const PlaylistSelectorDialog({super.key, required this.songFilenames});

  @override
  ConsumerState<PlaylistSelectorDialog> createState() =>
      _PlaylistSelectorDialogState();
}

class _PlaylistSelectorDialogState
    extends ConsumerState<PlaylistSelectorDialog> {
  late Set<String> _selectedPlaylistIds;
  late bool? _isFavorite; // null means mixed, true means all, false means none
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final userData = ref.read(userDataProvider);

      if (widget.songFilenames.length == 1) {
        final songFilename = widget.songFilenames[0];
        _isFavorite = userData.isFavorite(songFilename);
        _selectedPlaylistIds = userData.playlists
            .where(
                (pl) => pl.songs.any((ps) => ps.songFilename == songFilename))
            .map((pl) => pl.id)
            .toSet();
      } else {
        // Bulk mode
        int favoriteCount = 0;
        for (final f in widget.songFilenames) {
          if (userData.isFavorite(f)) favoriteCount++;
        }
        if (favoriteCount == 0) {
          _isFavorite = false;
        } else if (favoriteCount == widget.songFilenames.length) {
          _isFavorite = true;
        } else {
          _isFavorite = null; // Mixed
        }

        // For playlists in bulk mode, we only show as "selected" if ALL songs are in it?
        // Actually, maybe it's better to show as selected if ANY song is in it, or use a tri-state.
        // Let's use ANY for simplicity in initialization, but maybe null for mixed.
        _selectedPlaylistIds = {};
        for (final pl in userData.playlists) {
          bool anyIn = false;
          for (final f in widget.songFilenames) {
            if (pl.songs.any((ps) => ps.songFilename == f)) {
              anyIn = true;
              break;
            }
          }
          if (anyIn) {
            _selectedPlaylistIds.add(pl.id);
          }
        }
      }
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final playlists = userData.playlists;

    return AlertDialog(
      title: Text(
          widget.songFilenames.length == 1 ? 'Add to...' : 'Bulk Add to...'),
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
                  _showNewPlaylistDialog(context, ref, widget.songFilenames);
                },
              ),
              const Divider(),
              CheckboxListTile(
                title: const Text('Favorites'),
                secondary: const Icon(Icons.favorite, color: Colors.red),
                tristate: true,
                value: _isFavorite,
                onChanged: (val) {
                  setState(() => _isFavorite = val);
                },
              ),
              const Divider(),
              ...playlists.map((playlist) {
                final isSelected = _selectedPlaylistIds.contains(playlist.id);
                // In bulk mode, we could also use tri-state for playlists
                bool allIn = true;
                bool anyIn = false;
                for (final f in widget.songFilenames) {
                  if (playlist.songs.any((ps) => ps.songFilename == f)) {
                    anyIn = true;
                  } else {
                    allIn = false;
                  }
                }

                return CheckboxListTile(
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songs.length} songs'),
                  secondary: const Icon(Icons.queue_music),
                  tristate: widget.songFilenames.length > 1,
                  value: widget.songFilenames.length > 1
                      ? (allIn && isSelected
                          ? true
                          : (anyIn || isSelected ? null : false))
                      : isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPlaylistIds.add(playlist.id);
                      } else if (val == false) {
                        _selectedPlaylistIds.remove(playlist.id);
                      } else {
                        // For tri-state, if it becomes null, we keep it as "any" or something
                        // But usually we just toggle between true and false in bulk if user clicks
                        _selectedPlaylistIds.add(playlist.id);
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
            if (widget.songFilenames.length == 1) {
              if (_isFavorite !=
                  currentData.isFavorite(widget.songFilenames[0])) {
                await notifier.toggleFavorite(widget.songFilenames[0],
                    sync: false);
              }
            } else {
              if (_isFavorite == true) {
                await notifier.bulkToggleFavorite(widget.songFilenames, true);
              } else if (_isFavorite == false) {
                await notifier.bulkToggleFavorite(widget.songFilenames, false);
              }
            }

            // Handle Playlists
            for (final pl in playlists) {
              final isSelected = _selectedPlaylistIds.contains(pl.id);

              if (widget.songFilenames.length == 1) {
                final songFilename = widget.songFilenames[0];
                final wasIn =
                    pl.songs.any((ps) => ps.songFilename == songFilename);
                if (isSelected && !wasIn) {
                  await notifier.addSongToPlaylist(pl.id, songFilename,
                      sync: false);
                } else if (!isSelected && wasIn) {
                  await notifier.removeSongFromPlaylist(pl.id, songFilename,
                      sync: false);
                }
              } else {
                // Bulk mode
                // If isSelected is true, ensure ALL are in
                if (isSelected) {
                  final songsToAdd = widget.songFilenames
                      .where((f) => !pl.songs.any((ps) => ps.songFilename == f))
                      .toList();
                  if (songsToAdd.isNotEmpty) {
                    await notifier.bulkAddSongsToPlaylist(pl.id, songsToAdd);
                  }
                } else {
                  // If isSelected is false, ensure NONE are in
                  final songsToRemove = widget.songFilenames
                      .where((f) => pl.songs.any((ps) => ps.songFilename == f))
                      .toList();
                  if (songsToRemove.isNotEmpty) {
                    await notifier.bulkRemoveSongsFromPlaylist(
                        pl.id, songsToRemove);
                  }
                }
              }
            }

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
      BuildContext context, WidgetRef ref, List<String> songFilenames) {
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
              _createNewPlaylistAndAdd(
                  context, ref, value.trim(), songFilenames);
              Navigator.pop(dialogContext);
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
                _createNewPlaylistAndAdd(context, ref, name, songFilenames);
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewPlaylistAndAdd(BuildContext context, WidgetRef ref,
      String name, List<String> songFilenames) async {
    final notifier = ref.read(userDataProvider.notifier);
    if (songFilenames.length == 1) {
      await notifier.createPlaylist(name, songFilenames[0]);
    } else {
      await notifier.createPlaylist(name);
      // Find the newly created playlist (it's at the top)
      final newPlaylist = ref.read(userDataProvider).playlists.first;
      await notifier.bulkAddSongsToPlaylist(newPlaylist.id, songFilenames);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created playlist "$name"')),
      );
    }
  }
}

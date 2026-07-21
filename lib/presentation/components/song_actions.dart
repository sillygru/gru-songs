import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../screens/edit_metadata_screen.dart';
import '../screens/song_list_screen.dart';
import '../widgets/folder_picker.dart';
import '../widgets/playlist_selector_screen.dart';

/// Shared song actions, used by two surfaces: the full options menu
/// (`song_options_menu.dart`) and the player's configurable quick action bar
/// (`quick_action_bar.dart`).
///
/// These are deliberately free functions with no opinion about the widget that
/// triggered them — callers dismiss their own popup/sheet first, then invoke.
/// [host] must be a context that outlives that dismissal (the screen behind the
/// menu, not the menu itself), since these show snackbars and push routes.

/// Set [showFeedback] to false where the control itself already shows the new
/// state — a heart that fills in says everything a snackbar would.
void songActionToggleFavorite(
  BuildContext host,
  WidgetRef ref,
  String filename,
  String title, {
  bool showFeedback = true,
}) {
  final wasFavorite = ref.read(userDataProvider).isFavorite(filename);
  ref.read(userDataProvider.notifier).toggleFavorite(filename);
  if (!showFeedback || !host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(
      content: Text(
        wasFavorite
            ? 'Removed $title from favorites'
            : 'Added $title to favorites',
      ),
      duration: const Duration(seconds: 1),
    ),
  );
}

void songActionToggleSuggestLess(
  BuildContext host,
  WidgetRef ref,
  String filename,
  String title,
) {
  final wasSuggestLess = ref.read(userDataProvider).isSuggestLess(filename);
  ref.read(userDataProvider.notifier).toggleSuggestLess(filename);
  if (!host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(
      content: Text(
        wasSuggestLess
            ? 'Will suggest $title more often'
            : 'Will suggest $title less often',
      ),
      duration: const Duration(seconds: 1),
    ),
  );
}

void songActionPlayNext(BuildContext host, WidgetRef ref, Song song) {
  ref.read(audioPlayerManagerProvider).playNext(song);
  if (!host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(
      content: Text('Added to Next Up: ${song.title}'),
      duration: const Duration(seconds: 1),
    ),
  );
}

void songActionShare(Song song) {
  Share.shareXFiles(
    [XFile(song.url)],
    text: '${song.title} by ${song.artist}',
  );
}

/// Adds to the most recently updated playlist directly, offering a "Change"
/// escape hatch — falling back to the full selector when that would be
/// ambiguous (no playlists, or the song is already in the latest one).
void songActionAddToPlaylist(
  BuildContext host,
  WidgetRef ref,
  String filename,
) {
  final playlists = ref
      .read(userDataProvider)
      .playlists
      .where((p) => !p.isRecommendation)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  if (playlists.isEmpty) {
    showPlaylistSelector(host, ref, filename);
    return;
  }

  final latest = playlists.first;
  if (latest.songs.any((s) => s.songFilename == filename)) {
    showPlaylistSelector(host, ref, filename);
    return;
  }

  ref.read(userDataProvider.notifier).addSongToPlaylist(latest.id, filename);
  if (!host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(
      content: Text('Added to ${latest.name}'),
      action: SnackBarAction(
        label: 'Change',
        onPressed: () => showPlaylistSelector(host, ref, filename),
      ),
    ),
  );
}

void songActionAddToNewPlaylist(
  BuildContext host,
  WidgetRef ref,
  String filename,
) {
  final controller = TextEditingController();

  void create(BuildContext dialogContext, String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    ref.read(userDataProvider.notifier).createPlaylist(name, filename);
    Navigator.pop(dialogContext);
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Created playlist "$name"')),
    );
  }

  showDialog<void>(
    context: host,
    builder: (dialogContext) => AlertDialog(
      title: const Text('New Playlist'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Playlist Name'),
        autofocus: true,
        onSubmitted: (value) => create(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => create(dialogContext, controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

void songActionManagePlaylists(
  BuildContext host,
  WidgetRef ref,
  String filename,
) {
  showPlaylistSelector(host, ref, filename);
}

void songActionRemoveFromPlaylist(
  BuildContext host,
  WidgetRef ref,
  String playlistId,
  String filename,
  String title,
) {
  ref.read(userDataProvider.notifier).removeSongFromPlaylist(
        playlistId,
        filename,
      );
  if (!host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(
      content: Text('Removed $title from playlist'),
      action: SnackBarAction(
        label: 'Change',
        onPressed: () => showPlaylistSelector(host, ref, filename),
      ),
    ),
  );
}

void songActionEditMetadata(BuildContext host, Song song) {
  Navigator.push(
    host,
    MaterialPageRoute(builder: (_) => EditMetadataScreen(song: song)),
  );
}

Future<void> songActionMoveToFolder(
  BuildContext host,
  WidgetRef ref,
  Song song,
) async {
  final rootPath = await ref.read(storageServiceProvider).getMusicFolderPath();
  if (rootPath == null || !host.mounted) return;

  final targetPath = await showFolderPicker(host, rootPath);
  if (targetPath == null) return;

  try {
    await ref.read(songsProvider.notifier).moveSong(song, targetPath);
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Moved ${song.title} to $targetPath')),
    );
  } catch (e) {
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Error moving song: $e')),
    );
  }
}

Future<void> songActionHide(
  BuildContext host,
  WidgetRef ref,
  Song song,
) async {
  await ref.read(songsProvider.notifier).hideSong(song);
  if (!host.mounted) return;
  ScaffoldMessenger.of(host).showSnackBar(
    SnackBar(content: Text('Removed ${song.title} from library')),
  );
}

Future<void> songActionDelete(
  BuildContext host,
  WidgetRef ref,
  Song song,
) async {
  if (!host.mounted) return;

  final confirm = await showDialog<bool>(
        context: host,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Song'),
          content: Text(
            "Are you sure you want to permanently delete '${song.title}' from your device? This cannot be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Permanently'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirm) return;

  try {
    await ref.read(songsProvider.notifier).deleteSongFile(song);
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Deleted ${song.title}')),
    );
  } catch (e) {
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Error deleting file: $e')),
    );
  }
}

/// Opens the album this song belongs to. No-op when the library has not
/// finished loading, since there is nothing to filter yet.
void songActionGoToAlbum(BuildContext host, WidgetRef ref, Song song) {
  final songs = ref.read(songsProvider).value;
  if (songs == null) return;

  final albumSongs = songs.where((s) => s.album == song.album).toList();
  if (albumSongs.isEmpty) return;

  Navigator.push(
    host,
    MaterialPageRoute(
      builder: (_) => SongListScreen(title: song.album, songs: albumSongs),
    ),
  );
}

void songActionGoToArtist(BuildContext host, WidgetRef ref, Song song) {
  final songs = ref.read(songsProvider).value;
  if (songs == null) return;

  final artistSongs = songs.where((s) => s.artist == song.artist).toList();
  if (artistSongs.isEmpty) return;

  Navigator.push(
    host,
    MaterialPageRoute(
      builder: (_) => SongListScreen(title: song.artist, songs: artistSongs),
    ),
  );
}

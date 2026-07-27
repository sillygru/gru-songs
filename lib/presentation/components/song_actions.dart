import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/online_search_result.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/online_metadata_service.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';
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
      builder: (_) => SongListScreen(
        title: song.album,
        songs: albumSongs,
        isAlbum: true,
        albumName: song.album,
        artistName: song.artist,
      ),
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
      builder: (_) => SongListScreen(
        title: song.artist,
        songs: artistSongs,
        isArtist: true,
        artistName: song.artist,
      ),
    ),
  );
}

Future<void> songActionFetchMissingCover(
  BuildContext host,
  WidgetRef ref,
  Song song,
) async {
  ScaffoldMessenger.of(host).showSnackBar(
    const SnackBar(
      content: Text('Searching Deezer and iTunes for cover art...'),
      duration: Duration(seconds: 2),
    ),
  );

  try {
    final results =
        await OnlineMetadataService.instance.searchParallelForSong(song);
    OnlineSearchResult? match;

    for (final res in results) {
      if (res.coverUrl != null && res.coverUrl!.isNotEmpty) {
        match = res;
        break;
      }
    }

    if (match == null || match.coverUrl == null) {
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(
        const SnackBar(content: Text('No missing cover art found online')),
      );
      return;
    }

    final localPath =
        await OnlineMetadataService.instance.downloadAndCacheCover(
      match.coverUrl!,
      song.filename,
    );

    if (localPath != null && host.mounted) {
      await ref.read(songsProvider.notifier).updateSongCover(song, localPath);
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(
        SnackBar(
            content: Text(
                'Updated cover art for "${song.title}" (${match.source})')),
      );
    } else if (host.mounted) {
      ScaffoldMessenger.of(host).showSnackBar(
        const SnackBar(content: Text('Failed to download cover art')),
      );
    }
  } catch (e) {
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text('Error fetching cover: $e')),
    );
  }
}

class _MetadataUpdateRecord {
  final Song originalSong;
  final String newTitle;
  final String newArtist;
  final String newAlbum;
  final String? newCoverPath;

  _MetadataUpdateRecord({
    required this.originalSong,
    required this.newTitle,
    required this.newArtist,
    required this.newAlbum,
    this.newCoverPath,
  });
}

Future<void> _showMetadataResultsDialog(
  BuildContext context,
  WidgetRef ref,
  List<_MetadataUpdateRecord> updatedRecords,
  List<Song> notFoundSongs,
) async {
  if (updatedRecords.isEmpty && notFoundSongs.isEmpty) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Metadata Fetch Results'),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (updatedRecords.isNotEmpty) ...[
                    Text(
                      'Updated (${updatedRecords.length})',
                      style: AppTokens.rowTitle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTokens.success,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...updatedRecords.map((rec) => Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2.0),
                                child: AppIcon(
                                  AppIcons.checkCircle,
                                  color: AppTokens.success,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${rec.newTitle} · ${rec.newArtist}',
                                      style: AppTokens.rowTitle(context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Was: "${rec.originalSong.title}" by ${rec.originalSong.artist.isEmpty ? 'Unknown' : rec.originalSong.artist}',
                                      style: AppTokens.rowSubtitle(context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (notFoundSongs.isNotEmpty) const Divider(height: 24),
                  ],
                  if (notFoundSongs.isNotEmpty) ...[
                    Text(
                      'Could Not Find (${notFoundSongs.length})',
                      style: AppTokens.rowTitle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTokens.fgSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...notFoundSongs.map((song) => Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2.0),
                                child: AppIcon(
                                  AppIcons.searchOff,
                                  color: AppTokens.fgSecondary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title.isEmpty
                                          ? song.filename
                                          : song.title,
                                      style: AppTokens.rowTitle(context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      song.artist.isEmpty
                                          ? 'Unknown Artist'
                                          : song.artist,
                                      style: AppTokens.rowSubtitle(context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (updatedRecords.isNotEmpty)
            TextButton.icon(
              icon: const AppIcon(AppIcons.restore, size: 18),
              label: const Text('Undo'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                for (final rec in updatedRecords) {
                  await ref.read(songsProvider.notifier).updateSongMetadata(
                        rec.originalSong,
                        rec.originalSong.title,
                        rec.originalSong.artist,
                        rec.originalSong.album,
                      );
                  if (rec.originalSong.coverUrl != rec.newCoverPath) {
                    await ref.read(songsProvider.notifier).updateSongCover(
                          rec.originalSong,
                          rec.originalSong.coverUrl,
                        );
                  }
                }
                if (context.mounted) {
                  appSnack(context,
                      'Reverted metadata changes for ${updatedRecords.length} track(s)');
                }
              },
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}

Future<void> songActionFetchMissingMetadata(
  BuildContext host,
  WidgetRef ref,
  Song song,
) async {
  return songActionFetchMissingMetadataForList(host, ref, [song]);
}

Future<void> songActionFetchMissingMetadataForList(
  BuildContext host,
  WidgetRef ref,
  List<Song> songs,
) async {
  if (songs.isEmpty) return;

  appSnack(host,
      'Searching online for missing metadata (${songs.length} tracks)...');

  final onlineService = OnlineMetadataService.instance;
  final updatedRecords = <_MetadataUpdateRecord>[];
  final notFoundSongs = <Song>[];

  for (int i = 0; i < songs.length; i++) {
    final song = songs[i];
    try {
      final results = await onlineService.searchParallelForSong(song);
      if (results.isNotEmpty) {
        final match = results.first;

        String title = song.title;
        String artist = song.artist;
        String album = song.album;

        if (OnlineMetadataService.cleanTag(artist) == null) {
          artist = match.artist;
        }
        if (OnlineMetadataService.cleanTag(album) == null) {
          album = match.album;
        }
        if (OnlineMetadataService.cleanTag(title) == null) {
          title = match.title;
        }

        String? localCoverPath = song.coverUrl;
        if ((localCoverPath == null || localCoverPath.isEmpty) &&
            match.coverUrl != null &&
            match.coverUrl!.isNotEmpty) {
          localCoverPath = await onlineService.downloadAndCacheCover(
            match.coverUrl!,
            song.filename,
          );
        }

        final bool metadataChanged =
            title != song.title || artist != song.artist || album != song.album;
        final bool coverChanged =
            localCoverPath != null && localCoverPath != song.coverUrl;

        if (metadataChanged || coverChanged) {
          if (metadataChanged) {
            await ref
                .read(songsProvider.notifier)
                .updateSongMetadata(song, title, artist, album);
          }
          if (coverChanged) {
            await ref
                .read(songsProvider.notifier)
                .updateSongCover(song, localCoverPath);
          }
          updatedRecords.add(_MetadataUpdateRecord(
            originalSong: song,
            newTitle: title,
            newArtist: artist,
            newAlbum: album,
            newCoverPath: localCoverPath,
          ));
        } else {
          notFoundSongs.add(song);
        }
      } else {
        notFoundSongs.add(song);
      }
    } catch (_) {
      notFoundSongs.add(song);
    }
  }

  if (!host.mounted) return;
  await _showMetadataResultsDialog(host, ref, updatedRecords, notFoundSongs);
}

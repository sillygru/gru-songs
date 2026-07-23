import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../components/app_sheet.dart';
import '../components/song_actions.dart';
import '../tokens/app_tokens.dart';
import 'album_art_image.dart';

/// The per-song overflow menu.
///
/// This is a bottom sheet — the same surface every other options menu in the
/// app uses — rather than a centred pop-up, so the 3-dot menu stops reading as
/// a piece from a different app. Actions are grouped under small-caps labels and
/// the sheet is topped by the song it acts on.
void showSongOptionsMenu(
  BuildContext context,
  WidgetRef ref,
  String songFilename,
  String songTitle, {
  Song? song,
  String? playlistId,
}) {
  showAppSheet(
    context,
    builder: (sheetContext) => _SongOptionsSheet(
      parentContext: context,
      songFilename: songFilename,
      songTitle: songTitle,
      song: song,
      playlistId: playlistId,
    ),
  );
}

class _SongOptionsSheet extends ConsumerWidget {
  const _SongOptionsSheet({
    required this.parentContext,
    required this.songFilename,
    required this.songTitle,
    required this.song,
    required this.playlistId,
  });

  final BuildContext parentContext;
  final String songFilename;
  final String songTitle;
  final Song? song;
  final String? playlistId;

  void _run(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    action();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final isFavorite = userData.isFavorite(songFilename);
    final isSuggestLess = userData.isSuggestLess(songFilename);
    final accent = AppTokens.accentOf(context, ref);
    final hasSong = song != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, accent),
        const SizedBox(height: AppTokens.s2),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context, 'Playback'),
                if (hasSong)
                  AppSheetAction(
                    icon: Icons.queue_music_rounded,
                    label: 'Play Next',
                    description: 'Play right after the current track',
                    onTap: () => _run(context,
                        () => songActionPlayNext(parentContext, ref, song!)),
                  ),
                AppSheetAction(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to Playlist',
                  onTap: () => _run(
                      context,
                      () => songActionAddToPlaylist(
                          parentContext, ref, songFilename)),
                ),
                AppSheetAction(
                  icon: Icons.playlist_add_circle_outlined,
                  label: 'Add to New Playlist',
                  onTap: () => _run(
                      context,
                      () => songActionAddToNewPlaylist(
                          parentContext, ref, songFilename)),
                ),
                if (hasSong)
                  AppSheetAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: () => _run(context, () => songActionShare(song!)),
                  ),
                if (hasSong) ...[
                  _label(context, 'Library'),
                  AppSheetAction(
                    icon: Icons.drive_file_move_rounded,
                    label: 'Move to Folder',
                    onTap: () => _run(
                        context,
                        () =>
                            songActionMoveToFolder(parentContext, ref, song!)),
                  ),
                  AppSheetAction(
                    icon: Icons.playlist_add_check_rounded,
                    label: 'Manage Playlists',
                    onTap: () => _run(
                        context,
                        () => songActionManagePlaylists(
                            parentContext, ref, songFilename)),
                  ),
                  AppSheetAction(
                    icon: Icons.edit_rounded,
                    label: 'Edit Metadata',
                    onTap: () => _run(context,
                        () => songActionEditMetadata(parentContext, song!)),
                  ),
                ],
                _label(context, 'Personalize'),
                AppSheetAction(
                  icon: isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label:
                      isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                  trailing: isFavorite
                      ? Icon(Icons.favorite_rounded, size: 18, color: accent)
                      : null,
                  onTap: () => _run(
                      context,
                      () => songActionToggleFavorite(
                          parentContext, ref, songFilename, songTitle)),
                ),
                AppSheetAction(
                  icon: isSuggestLess
                      ? Icons.thumb_up_alt_outlined
                      : Icons.heart_broken_outlined,
                  label: isSuggestLess ? 'Suggest More' : 'Suggest Less',
                  onTap: () => _run(
                      context,
                      () => songActionToggleSuggestLess(
                          parentContext, ref, songFilename, songTitle)),
                ),
                if (playlistId != null || hasSong) _label(context, 'Remove'),
                if (playlistId != null)
                  AppSheetAction(
                    icon: Icons.playlist_remove_rounded,
                    label: 'Remove from this Playlist',
                    isDanger: true,
                    onTap: () => _run(
                        context,
                        () => songActionRemoveFromPlaylist(parentContext, ref,
                            playlistId!, songFilename, songTitle)),
                  ),
                if (hasSong) ...[
                  AppSheetAction(
                    icon: Icons.visibility_off_rounded,
                    label: 'Hide from Library',
                    isDanger: true,
                    onTap: () => _run(context,
                        () => songActionHide(parentContext, ref, song!)),
                  ),
                  AppSheetAction(
                    icon: Icons.delete_rounded,
                    label: 'Delete Permanently',
                    isDanger: true,
                    onTap: () => _run(context,
                        () => songActionDelete(parentContext, ref, song!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        0,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppTokens.brSm,
            child: SizedBox(
              width: 52,
              height: 52,
              child: song != null
                  ? AlbumArtImage(
                      url: song!.coverUrl ?? '',
                      filename: song!.filename,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      memCacheHeight: 120,
                    )
                  : ColoredBox(
                      color: AppTokens.surface(2),
                      child: Icon(Icons.music_note_rounded,
                          color: AppTokens.fgTertiary),
                    ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  songTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.rowTitle(context),
                ),
                if (song != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    song!.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.rowSubtitle(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s3,
        AppTokens.s5,
        AppTokens.s1,
      ),
      child: Text(text.toUpperCase(), style: AppTokens.sectionLabel(context)),
    );
  }
}

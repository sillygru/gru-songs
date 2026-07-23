import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../components/press_highlight.dart';
import '../components/song_actions.dart';
import '../tokens/app_tokens.dart';
import 'album_art_image.dart';

/// The per-song overflow menu.
///
/// A compact popup anchored at the tap point — not a full-height bottom sheet.
/// It reads as part of the immersive surface: a near-black fill tinted by the
/// current cover colour, rounded, no outline, no glass. Actions are grouped
/// under small-caps labels and topped by the song it acts on.
///
/// [anchor] is the global position of the control that opened it (the ⋮ button
/// or the long-pressed row); the menu opens beside it and flips above when
/// there isn't room below. A null anchor falls back to centre.
void showSongOptionsMenu(
  BuildContext context,
  WidgetRef ref,
  String songFilename,
  String songTitle, {
  Song? song,
  String? playlistId,
  Offset? anchor,
}) {
  final screenWidth = MediaQuery.of(context).size.width;
  final menuWidth = screenWidth - AppTokens.s5 * 2 < 300
      ? screenWidth - AppTokens.s5 * 2
      : 300.0;

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Song options',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, _, __) {
      return CustomSingleChildLayout(
        delegate: _PopupLayoutDelegate(anchor: anchor),
        child: SizedBox(
          width: menuWidth,
          child: _SongOptionsPopup(
            parentContext: context,
            songFilename: songFilename,
            songTitle: songTitle,
            song: song,
            playlistId: playlistId,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          alignment: anchor != null ? Alignment.topRight : Alignment.center,
          child: child,
        ),
      );
    },
  );
}

/// Positions the popup beside [anchor], flipping above / clamping to the screen
/// once the child's measured size is known.
class _PopupLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset? anchor;

  const _PopupLayoutDelegate({this.anchor});

  static const double _gap = 8;
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(constraints.maxWidth, constraints.maxHeight - _margin * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = this.anchor;
    if (anchor == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    // Right edge of the menu sits just under the tapped control.
    var left = anchor.dx - childSize.width + 20;
    left = left.clamp(_margin, size.width - childSize.width - _margin);

    var top = anchor.dy + _gap;
    if (top + childSize.height > size.height - _margin) {
      // Not enough room below — flip above the anchor.
      top = anchor.dy - childSize.height - _gap;
    }
    top = top.clamp(_margin, size.height - childSize.height - _margin);

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopupLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _SongOptionsPopup extends ConsumerWidget {
  const _SongOptionsPopup({
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

  void _run(BuildContext popupContext, VoidCallback action) {
    Navigator.pop(popupContext);
    action();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final isFavorite = userData.isFavorite(songFilename);
    final isSuggestLess = userData.isSuggestLess(songFilename);
    final accent = AppTokens.accentOf(context, ref);
    final hasSong = song != null;

    // Near-black, cover-tinted — the same surface language as the now-playing
    // bar and ambient backdrop.
    final fill = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      Color.alphaBlend(
        AppTokens.surface(2),
        Theme.of(context).scaffoldBackgroundColor,
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: AppTokens.brLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppTokens.s2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, 'Playback'),
                    if (hasSong)
                      _action(
                        context,
                        icon: Icons.queue_music_rounded,
                        label: 'Play Next',
                        onTap: () => _run(
                            context,
                            () =>
                                songActionPlayNext(parentContext, ref, song!)),
                      ),
                    _action(
                      context,
                      icon: Icons.playlist_add_rounded,
                      label: 'Add to Playlist',
                      onTap: () => _run(
                          context,
                          () => songActionAddToPlaylist(
                              parentContext, ref, songFilename)),
                    ),
                    _action(
                      context,
                      icon: Icons.playlist_add_circle_outlined,
                      label: 'Add to New Playlist',
                      onTap: () => _run(
                          context,
                          () => songActionAddToNewPlaylist(
                              parentContext, ref, songFilename)),
                    ),
                    if (hasSong)
                      _action(
                        context,
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        onTap: () =>
                            _run(context, () => songActionShare(song!)),
                      ),
                    if (hasSong) ...[
                      _label(context, 'Library'),
                      _action(
                        context,
                        icon: Icons.drive_file_move_rounded,
                        label: 'Move to Folder',
                        onTap: () => _run(
                            context,
                            () => songActionMoveToFolder(
                                parentContext, ref, song!)),
                      ),
                      _action(
                        context,
                        icon: Icons.playlist_add_check_rounded,
                        label: 'Manage Playlists',
                        onTap: () => _run(
                            context,
                            () => songActionManagePlaylists(
                                parentContext, ref, songFilename)),
                      ),
                      _action(
                        context,
                        icon: Icons.edit_rounded,
                        label: 'Edit Metadata',
                        onTap: () => _run(context,
                            () => songActionEditMetadata(parentContext, song!)),
                      ),
                    ],
                    _label(context, 'Personalize'),
                    _action(
                      context,
                      icon: isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      iconColor: isFavorite ? accent : null,
                      label: isFavorite
                          ? 'Remove from Favorites'
                          : 'Add to Favorites',
                      onTap: () => _run(
                          context,
                          () => songActionToggleFavorite(
                              parentContext, ref, songFilename, songTitle)),
                    ),
                    _action(
                      context,
                      icon: isSuggestLess
                          ? Icons.thumb_up_alt_outlined
                          : Icons.heart_broken_outlined,
                      label: isSuggestLess ? 'Suggest More' : 'Suggest Less',
                      onTap: () => _run(
                          context,
                          () => songActionToggleSuggestLess(
                              parentContext, ref, songFilename, songTitle)),
                    ),
                    if (playlistId != null || hasSong)
                      _label(context, 'Remove'),
                    if (playlistId != null)
                      _action(
                        context,
                        icon: Icons.playlist_remove_rounded,
                        label: 'Remove from this Playlist',
                        isDanger: true,
                        onTap: () => _run(
                            context,
                            () => songActionRemoveFromPlaylist(parentContext,
                                ref, playlistId!, songFilename, songTitle)),
                      ),
                    if (hasSong) ...[
                      _action(
                        context,
                        icon: Icons.visibility_off_rounded,
                        label: 'Hide from Library',
                        isDanger: true,
                        onTap: () => _run(context,
                            () => songActionHide(parentContext, ref, song!)),
                      ),
                      _action(
                        context,
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
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s3,
        AppTokens.s3,
        AppTokens.s3,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppTokens.brSm,
            child: SizedBox(
              width: 44,
              height: 44,
              child: song != null
                  ? AlbumArtImage(
                      url: song!.coverUrl ?? '',
                      filename: song!.filename,
                      fit: BoxFit.cover,
                      memCacheWidth: 104,
                      memCacheHeight: 104,
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
                  style: AppTokens.rowTitle(context).copyWith(fontSize: 15),
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
        AppTokens.s4,
        AppTokens.s3,
        AppTokens.s4,
        AppTokens.s1,
      ),
      child: Text(text.toUpperCase(), style: AppTokens.sectionLabel(context)),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDanger = false,
  }) {
    final color = isDanger ? AppTokens.danger : AppTokens.fgPrimary;
    return PressHighlight(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? color),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.rowTitle(context).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

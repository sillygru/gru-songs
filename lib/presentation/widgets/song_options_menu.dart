import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../screens/edit_metadata_screen.dart';
import 'folder_picker.dart';
import 'playlist_selector_screen.dart';

void showSongOptionsMenu(
  BuildContext context,
  WidgetRef ref,
  String songFilename,
  String songTitle, {
  Song? song,
  String? playlistId,
}) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Song options',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return SafeArea(
        child: Center(
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
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

enum _SongMenuView {
  root,
  playback,
  library,
  personalize,
  danger,
}

class _SongOptionsPopup extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<_SongOptionsPopup> createState() => _SongOptionsPopupState();
}

class _SongOptionsPopupState extends ConsumerState<_SongOptionsPopup>
    with TickerProviderStateMixin {
  _SongMenuView _view = _SongMenuView.root;
  int _direction = 1;

  int _viewIndex(_SongMenuView view) {
    switch (view) {
      case _SongMenuView.root:
        return 0;
      case _SongMenuView.playback:
        return 1;
      case _SongMenuView.library:
        return 2;
      case _SongMenuView.personalize:
        return 3;
      case _SongMenuView.danger:
        return 4;
    }
  }

  void _goTo(_SongMenuView next) {
    if (!mounted) return;
    final currentIndex = _viewIndex(_view);
    final nextIndex = _viewIndex(next);
    setState(() {
      _direction = nextIndex >= currentIndex ? 1 : -1;
      _view = next;
    });
  }

  void _closePopup() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleFavorite(bool isFavorite) {
    ref.read(userDataProvider.notifier).toggleFavorite(widget.songFilename);
    _closePopup();
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text(
          isFavorite
              ? 'Removed ${widget.songTitle} from favorites'
              : 'Added ${widget.songTitle} to favorites',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleSuggestLess(bool isSuggestLess) {
    ref.read(userDataProvider.notifier).toggleSuggestLess(widget.songFilename);
    _closePopup();
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text(
          isSuggestLess
              ? 'Will suggest ${widget.songTitle} more often'
              : 'Will suggest ${widget.songTitle} less often',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handlePlayNext() async {
    final song = widget.song;
    if (song == null) return;

    ref.read(audioPlayerManagerProvider).playNext(song);
    _closePopup();
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text('Added to Next Up: ${song.title}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleMoveToFolder() async {
    final song = widget.song;
    if (song == null) return;

    _closePopup();

    final storage = ref.read(storageServiceProvider);
    final rootPath = await storage.getMusicFolderPath();
    if (rootPath == null || !widget.parentContext.mounted) return;

    final targetPath = await showFolderPicker(widget.parentContext, rootPath);
    if (targetPath == null) return;

    try {
      await ref.read(songsProvider.notifier).moveSong(song, targetPath);
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text('Moved ${song.title} to $targetPath')),
        );
      }
    } catch (e) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text('Error moving song: $e')),
        );
      }
    }
  }

  void _handleAddToPlaylist() {
    _closePopup();

    final playlists = ref.read(userDataProvider).playlists;
    final sorted = List.of(playlists)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (sorted.isEmpty) {
      showPlaylistSelector(widget.parentContext, ref, widget.songFilename);
      return;
    }

    final latest = sorted.first;
    if (latest.songs.any((s) => s.songFilename == widget.songFilename)) {
      showPlaylistSelector(widget.parentContext, ref, widget.songFilename);
      return;
    }

    ref
        .read(userDataProvider.notifier)
        .addSongToPlaylist(latest.id, widget.songFilename);
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text('Added to ${latest.name}'),
        action: SnackBarAction(
          label: 'Change',
          onPressed: () {
            showPlaylistSelector(
                widget.parentContext, ref, widget.songFilename);
          },
        ),
      ),
    );
  }

  void _handleAddToNewPlaylist() {
    _closePopup();

    final controller = TextEditingController();
    showDialog<void>(
      context: widget.parentContext,
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
                  .createPlaylist(value.trim(), widget.songFilename);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(widget.parentContext).showSnackBar(
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
                    .createPlaylist(name, widget.songFilename);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(widget.parentContext).showSnackBar(
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

  void _handleShare() {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    Share.shareXFiles(
      [XFile(song.url)],
      text: '${song.title} by ${song.artist}',
    );
  }

  void _handleRemoveFromCurrentPlaylist() {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    ref
        .read(userDataProvider.notifier)
        .removeSongFromPlaylist(playlistId, widget.songFilename);
    _closePopup();
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text('Removed ${widget.songTitle} from playlist'),
        action: SnackBarAction(
          label: 'Change',
          onPressed: () {
            showPlaylistSelector(
                widget.parentContext, ref, widget.songFilename);
          },
        ),
      ),
    );
  }

  void _handleEditMetadata() {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    Navigator.push(
      widget.parentContext,
      MaterialPageRoute(builder: (context) => EditMetadataScreen(song: song)),
    );
  }

  void _handleManagePlaylists() {
    _closePopup();
    showPlaylistSelector(context, ref, widget.songFilename);
  }

  Future<void> _handleHideFromLibrary() async {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    await ref.read(songsProvider.notifier).hideSong(song);
    if (widget.parentContext.mounted) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(content: Text('Removed ${song.title} from library')),
      );
    }
  }

  Future<void> _handleDeleteSong() async {
    final song = widget.song;
    if (song == null || !widget.parentContext.mounted) return;

    _closePopup();

    final confirm = await showDialog<bool>(
          context: widget.parentContext,
          builder: (context) => AlertDialog(
            title: const Text('Delete Song'),
            content: Text(
              "Are you sure you want to permanently delete '${song.title}' from your device? This cannot be undone.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
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
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text('Deleted ${song.title}')),
        );
      }
    } catch (e) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(content: Text('Error deleting file: $e')),
        );
      }
    }
  }

  Widget _submenuEntry({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (iconColor ?? Theme.of(context).colorScheme.primary)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Text(label),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRootView({
    required bool isFavorite,
    required bool isSuggestLess,
    required bool isCurrentlyPlaying,
  }) {
    final hasSongActions = widget.song != null;

    return Column(
      key: const ValueKey(_SongMenuView.root),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSongActions)
          _sectionCard(
            icon: Icons.play_arrow_rounded,
            title: 'Playback',
            subtitle: 'Queue, playlist, and share actions',
            onTap: () => _goTo(_SongMenuView.playback),
          ),
        if (hasSongActions) const SizedBox(height: 8),
        if (hasSongActions)
          _sectionCard(
            icon: Icons.folder_open_rounded,
            title: 'Library',
            subtitle: isCurrentlyPlaying
                ? 'Move and metadata edit (editing disabled while playing)'
                : 'Move song and edit metadata',
            onTap: () => _goTo(_SongMenuView.library),
          ),
        if (hasSongActions) const SizedBox(height: 8),
        _sectionCard(
          icon: Icons.favorite_rounded,
          title: 'Personalize',
          subtitle: 'Favorite and recommendation settings',
          onTap: () => _goTo(_SongMenuView.personalize),
          accent:
              isFavorite ? Colors.red : Theme.of(context).colorScheme.secondary,
        ),
        if (hasSongActions) const SizedBox(height: 8),
        if (hasSongActions)
          _sectionCard(
            icon: Icons.delete_outline_rounded,
            title: 'Danger Zone',
            subtitle: 'Remove from playlist or delete song',
            onTap: () => _goTo(_SongMenuView.danger),
            accent: Colors.red,
          ),
      ],
    );
  }

  Widget _buildPlaybackView() {
    return Column(
      key: const ValueKey(_SongMenuView.playback),
      children: [
        _submenuEntry(
          icon: Icons.queue_music_rounded,
          label: 'Play Next',
          subtitle: 'Add song to play immediately after current track',
          onTap: _handlePlayNext,
        ),
        _submenuEntry(
          icon: Icons.playlist_add_rounded,
          label: 'Add to Playlist',
          subtitle: 'Quick add to your most recent playlist',
          onTap: _handleAddToPlaylist,
        ),
        _submenuEntry(
          icon: Icons.playlist_add_circle_outlined,
          label: 'Add to New Playlist',
          subtitle: 'Create a playlist and add this song',
          onTap: _handleAddToNewPlaylist,
        ),
        _submenuEntry(
          icon: Icons.share_rounded,
          label: 'Share',
          subtitle: 'Share the audio file externally',
          onTap: _handleShare,
        ),
      ],
    );
  }

  Widget _buildLibraryView({required bool isCurrentlyPlaying}) {
    return Column(
      key: const ValueKey(_SongMenuView.library),
      children: [
        _submenuEntry(
          icon: Icons.drive_file_move_outline,
          label: 'Move to Folder',
          subtitle: 'Move this file to another folder',
          onTap: _handleMoveToFolder,
        ),
        _submenuEntry(
          icon: Icons.playlist_add_check_rounded,
          label: 'Manage Playlists',
          subtitle: 'Add or remove from playlists',
          onTap: _handleManagePlaylists,
        ),
        Opacity(
          opacity: isCurrentlyPlaying ? 0.45 : 1,
          child: IgnorePointer(
            ignoring: isCurrentlyPlaying,
            child: _submenuEntry(
              icon: Icons.edit_outlined,
              label: 'Edit Metadata',
              subtitle: isCurrentlyPlaying
                  ? 'Unavailable while this song is playing'
                  : 'Open metadata editor',
              onTap: _handleEditMetadata,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalizeView({
    required bool isFavorite,
    required bool isSuggestLess,
  }) {
    return Column(
      key: const ValueKey(_SongMenuView.personalize),
      children: [
        _submenuEntry(
          icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border,
          iconColor: isFavorite ? Colors.red : null,
          label: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: 'Tune your favorite songs list',
          onTap: () => _toggleFavorite(isFavorite),
        ),
        _submenuEntry(
          icon: Icons.heart_broken_outlined,
          iconColor: isSuggestLess ? Colors.grey : null,
          label: isSuggestLess ? 'Suggest More' : 'Suggest Less',
          subtitle: 'Adjust how often this song appears in suggestions',
          onTap: () => _toggleSuggestLess(isSuggestLess),
        ),
      ],
    );
  }

  Widget _buildDangerView() {
    return Column(
      key: const ValueKey(_SongMenuView.danger),
      children: [
        if (widget.playlistId != null)
          _submenuEntry(
            icon: Icons.playlist_remove_rounded,
            iconColor: Colors.red,
            label: 'Remove from Current Playlist',
            subtitle: 'Keep file, remove playlist mapping',
            onTap: _handleRemoveFromCurrentPlaylist,
          ),
        _submenuEntry(
          icon: Icons.visibility_off_rounded,
          iconColor: Colors.grey,
          label: 'Remove from Library',
          subtitle: 'Keep file but hide from the library',
          onTap: _handleHideFromLibrary,
        ),
        _submenuEntry(
          icon: Icons.delete_outline_rounded,
          iconColor: Colors.red,
          label: 'Delete Permanently',
          subtitle: 'Delete the file from the device',
          onTap: _handleDeleteSong,
        ),
      ],
    );
  }

  Widget _buildAnimatedMenuContent({
    required bool isFavorite,
    required bool isSuggestLess,
    required bool isCurrentlyPlaying,
  }) {
    Widget child;
    switch (_view) {
      case _SongMenuView.root:
        child = _buildRootView(
          isFavorite: isFavorite,
          isSuggestLess: isSuggestLess,
          isCurrentlyPlaying: isCurrentlyPlaying,
        );
        break;
      case _SongMenuView.playback:
        child = _buildPlaybackView();
        break;
      case _SongMenuView.library:
        child = _buildLibraryView(isCurrentlyPlaying: isCurrentlyPlaying);
        break;
      case _SongMenuView.personalize:
        child = _buildPersonalizeView(
          isFavorite: isFavorite,
          isSuggestLess: isSuggestLess,
        );
        break;
      case _SongMenuView.danger:
        child = _buildDangerView();
        break;
    }

    final offset = _direction >= 0 ? 0.14 : -0.14;

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(offset, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final isFavorite = userData.isFavorite(widget.songFilename);
    final isSuggestLess = userData.isSuggestLess(widget.songFilename);

    final currentSong =
        ref.read(audioPlayerManagerProvider).currentSongNotifier.value;
    final isCurrentlyPlaying = currentSong?.filename == widget.songFilename;

    final theme = Theme.of(context);
    final canGoBack = _view != _SongMenuView.root;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 20,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.9),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (canGoBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => _goTo(_SongMenuView.root),
                        tooltip: 'Back',
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            widget.songTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            switch (_view) {
                              _SongMenuView.root => 'Song Options',
                              _SongMenuView.playback => 'Playback',
                              _SongMenuView.library => 'Library',
                              _SongMenuView.personalize => 'Personalize',
                              _SongMenuView.danger => 'Danger Zone',
                            },
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _closePopup,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: _buildAnimatedMenuContent(
                    isFavorite: isFavorite,
                    isSuggestLess: isSuggestLess,
                    isCurrentlyPlaying: isCurrentlyPlaying,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

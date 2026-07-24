import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../components/song_actions.dart';
import '../tokens/app_tokens.dart';

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
    _closePopup();
    songActionToggleFavorite(
      widget.parentContext,
      ref,
      widget.songFilename,
      widget.songTitle,
    );
  }

  void _toggleSuggestLess(bool isSuggestLess) {
    _closePopup();
    songActionToggleSuggestLess(
      widget.parentContext,
      ref,
      widget.songFilename,
      widget.songTitle,
    );
  }

  Future<void> _handlePlayNext() async {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    songActionPlayNext(widget.parentContext, ref, song);
  }

  Future<void> _handleMoveToFolder() async {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    await songActionMoveToFolder(widget.parentContext, ref, song);
  }

  void _handleAddToPlaylist() {
    _closePopup();
    songActionAddToPlaylist(widget.parentContext, ref, widget.songFilename);
  }

  void _handleAddToNewPlaylist() {
    _closePopup();
    songActionAddToNewPlaylist(widget.parentContext, ref, widget.songFilename);
  }

  void _handleShare() {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    songActionShare(song);
  }

  void _handleRemoveFromCurrentPlaylist() {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    _closePopup();
    songActionRemoveFromPlaylist(
      widget.parentContext,
      ref,
      playlistId,
      widget.songFilename,
      widget.songTitle,
    );
  }

  void _handleEditMetadata() {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    songActionEditMetadata(widget.parentContext, song);
  }

  void _handleManagePlaylists() {
    _closePopup();
    songActionManagePlaylists(widget.parentContext, ref, widget.songFilename);
  }

  Future<void> _handleHideFromLibrary() async {
    final song = widget.song;
    if (song == null) return;

    _closePopup();
    await songActionHide(widget.parentContext, ref, song);
  }

  Future<void> _handleDeleteSong() async {
    final song = widget.song;
    if (song == null || !widget.parentContext.mounted) return;

    _closePopup();
    await songActionDelete(widget.parentContext, ref, song);
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
          borderRadius: AppTokens.brSm,
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
      borderRadius: AppTokens.brSm,
      child: InkWell(
        borderRadius: AppTokens.brSm,
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
                  borderRadius: AppTokens.brSm,
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
            subtitle: 'Move song and edit metadata',
            onTap: () => _goTo(_SongMenuView.library),
          ),
        if (hasSongActions) const SizedBox(height: 8),
        _sectionCard(
          icon: Icons.favorite_rounded,
          title: 'Personalize',
          subtitle: 'Favorite and recommendation settings',
          onTap: () => _goTo(_SongMenuView.personalize),
          accent: isFavorite
              ? AppTokens.danger
              : Theme.of(context).colorScheme.secondary,
        ),
        if (hasSongActions) const SizedBox(height: 8),
        if (hasSongActions)
          _sectionCard(
            icon: Icons.delete_outline_rounded,
            title: 'Danger Zone',
            subtitle: 'Remove from playlist or delete song',
            onTap: () => _goTo(_SongMenuView.danger),
            accent: AppTokens.danger,
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
          icon: Icons.queue_music_rounded,
          label: 'Play Next (Allow Duplicate)',
          subtitle: 'Add again even if already in queue',
          onTap: () async {
            _closePopup();
            if (widget.song == null) return;
            ref
                .read(audioPlayerManagerProvider)
                .playNext(widget.song!, allowDuplicate: true);
            if (widget.parentContext.mounted) {
              ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                SnackBar(
                  content: Text('Added to Next Up: ${widget.song!.title}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
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

  Widget _buildLibraryView() {
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
        _submenuEntry(
          icon: Icons.edit_outlined,
          label: 'Edit Metadata',
          subtitle: 'Open metadata editor',
          onTap: _handleEditMetadata,
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
          iconColor: isFavorite ? AppTokens.danger : null,
          label: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: 'Tune your favorite songs list',
          onTap: () => _toggleFavorite(isFavorite),
        ),
        _submenuEntry(
          icon: Icons.heart_broken_outlined,
          iconColor: isSuggestLess ? AppTokens.fgTertiary : null,
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
            iconColor: AppTokens.danger,
            label: 'Remove from Current Playlist',
            subtitle: 'Keep file, remove playlist mapping',
            onTap: _handleRemoveFromCurrentPlaylist,
          ),
        _submenuEntry(
          icon: Icons.visibility_off_rounded,
          iconColor: AppTokens.fgTertiary,
          label: 'Remove from Library',
          subtitle: 'Keep file but hide from the library',
          onTap: _handleHideFromLibrary,
        ),
        _submenuEntry(
          icon: Icons.delete_outline_rounded,
          iconColor: AppTokens.danger,
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
  }) {
    Widget child;
    switch (_view) {
      case _SongMenuView.root:
        child = _buildRootView(
          isFavorite: isFavorite,
          isSuggestLess: isSuggestLess,
        );
        break;
      case _SongMenuView.playback:
        child = _buildPlaybackView();
        break;
      case _SongMenuView.library:
        child = _buildLibraryView();
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

    final theme = Theme.of(context);
    final canGoBack = _view != _SongMenuView.root;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
      child: Material(
        color: Color.alphaBlend(
          AppTokens.surface(2),
          theme.scaffoldBackgroundColor,
        ),
        elevation: 0,
        borderRadius: AppTokens.brLg,
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s2,
                  vertical: AppTokens.s2,
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

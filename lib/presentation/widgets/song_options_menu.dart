import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/providers.dart';
import '../components/song_actions.dart';
import '../tokens/app_tokens.dart';
import '../components/app_icon.dart';
import '../components/app_list_row.dart';
import '../tokens/app_icons.dart';

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

  /// A leaf action inside one of the submenus.
  ///
  /// This menu used to hand-roll its rows — its own [ListTile], its own icon
  /// plate at its own size, its own type. It now goes through [AppListRow] like
  /// every other list in the app, so the leading-slot geometry and the type
  /// ramp stay in one place.
  Widget _submenuEntry({
    required AppIconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return AppListRow(
      dense: true,
      leading: AppRowIcon(icon: icon, color: iconColor, size: 40),
      title: label,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  /// One of the four top-level groups.
  ///
  /// The card behind it stays a neutral fill. Washing the whole card in the
  /// accent turned every group into a coloured slab and left the destructive
  /// one indistinguishable at a glance — now only its glyph is red, which is
  /// the one thing that needs to catch the eye.
  Widget _sectionCard({
    required AppIconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? accent,
  }) {
    // Flat fill rather than an [AppSurface]: these cards already sit inside the
    // floating menu, and a raised shadow on each one would stack against the
    // menu's own.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface(1),
        borderRadius: AppTokens.brMd,
      ),
      child: AppListRow(
        leading: AppRowIcon(icon: icon, color: accent),
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: const AppIcon(
          AppIcons.chevronRight,
          size: AppTokens.iconSm,
          color: AppTokens.fgTertiary,
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
            icon: AppIcons.play,
            title: 'Playback',
            subtitle: 'Queue, playlist, and share actions',
            onTap: () => _goTo(_SongMenuView.playback),
          ),
        if (hasSongActions) const SizedBox(height: AppTokens.s2),
        if (hasSongActions)
          _sectionCard(
            icon: AppIcons.folder,
            title: 'Library',
            subtitle: 'Move song and edit metadata',
            onTap: () => _goTo(_SongMenuView.library),
          ),
        if (hasSongActions) const SizedBox(height: AppTokens.s2),
        _sectionCard(
          icon: AppIcons.favorite,
          title: 'Personalize',
          subtitle: 'Favorite and recommendation settings',
          onTap: () => _goTo(_SongMenuView.personalize),
          // Red only while the song *is* favourited — otherwise the glyph takes
          // the cover accent like the rest.
          accent: isFavorite ? AppTokens.danger : null,
        ),
        if (hasSongActions) const SizedBox(height: AppTokens.s2),
        if (hasSongActions)
          _sectionCard(
            icon: AppIcons.delete,
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
          icon: AppIcons.queue,
          label: 'Play Next',
          subtitle: 'Add song to play immediately after current track',
          onTap: _handlePlayNext,
        ),
        _submenuEntry(
          icon: AppIcons.queue,
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
          icon: AppIcons.playlistAdd,
          label: 'Add to Playlist',
          subtitle: 'Quick add to your most recent playlist',
          onTap: _handleAddToPlaylist,
        ),
        _submenuEntry(
          icon: AppIcons.playlistAdd,
          label: 'Add to New Playlist',
          subtitle: 'Create a playlist and add this song',
          onTap: _handleAddToNewPlaylist,
        ),
        _submenuEntry(
          icon: AppIcons.share,
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
          icon: AppIcons.imageSearch,
          label: 'Fetch Missing Cover',
          subtitle: 'Try searching Last.fm, Deezer and iTunes for cover art',
          onTap: () async {
            final song = widget.song;
            if (song == null) return;
            _closePopup();
            await songActionFetchMissingCover(widget.parentContext, ref, song);
          },
        ),
        _submenuEntry(
          icon: AppIcons.manageSearch,
          label: 'Fetch Missing Metadata',
          subtitle: 'Search online for title, artist, album and cover',
          onTap: () async {
            final song = widget.song;
            if (song == null) return;
            _closePopup();
            await songActionFetchMissingMetadata(
                widget.parentContext, ref, song);
          },
        ),
        _submenuEntry(
          icon: AppIcons.folderMove,
          label: 'Move to Folder',
          subtitle: 'Move this file to another folder',
          onTap: _handleMoveToFolder,
        ),
        _submenuEntry(
          icon: AppIcons.playlistAdd,
          label: 'Manage Playlists',
          subtitle: 'Add or remove from playlists',
          onTap: _handleManagePlaylists,
        ),
        _submenuEntry(
          icon: AppIcons.edit,
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
          icon: isFavorite ? AppIcons.favorite : AppIcons.favorite,
          iconColor: isFavorite ? AppTokens.danger : null,
          label: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: 'Tune your favorite songs list',
          onTap: () => _toggleFavorite(isFavorite),
        ),
        _submenuEntry(
          icon: AppIcons.heartBroken,
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
            icon: AppIcons.playlistRemove,
            iconColor: AppTokens.danger,
            label: 'Remove from Current Playlist',
            subtitle: 'Keep file, remove playlist mapping',
            onTap: _handleRemoveFromCurrentPlaylist,
          ),
        _submenuEntry(
          icon: AppIcons.visibilityOff,
          iconColor: AppTokens.fgTertiary,
          label: 'Remove from Library',
          subtitle: 'Keep file but hide from the library',
          onTap: _handleHideFromLibrary,
        ),
        _submenuEntry(
          icon: AppIcons.delete,
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
        // The options popup is the top-most floating plane — lift it off the
        // dimmed page, but no harder than the dialog theme lifts its own, or it
        // reads as a heavier design language than the rest of the app.
        elevation: 8,
        shadowColor: const Color(0x4D000000),
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
                        icon: const AppIcon(AppIcons.arrowBack),
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
                            style: AppTokens.paneTitle(context)
                                .copyWith(fontSize: 16),
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
                      icon: const AppIcon(AppIcons.close),
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

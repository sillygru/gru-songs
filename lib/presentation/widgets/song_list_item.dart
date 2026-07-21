import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/selection_provider.dart';
import '../../services/audio_player_manager.dart';
import '../components/app_list_row.dart';
import '../tokens/app_tokens.dart';
import 'album_art_image.dart';
import 'song_options_menu.dart';
import 'audio_visualizer.dart';
import 'duration_display.dart';

/// A song in any of the app's lists.
///
/// Thin wrapper over [AppListRow] — the row's anatomy, spacing, type and active
/// treatment come from there, so a song here and a song in the player's queue
/// read as the same object. What stays local is what is genuinely specific:
/// the Hero tag, the selection/visualizer overlays and the trailing actions.
class SongListItem extends ConsumerWidget {
  final Song song;
  final bool? isPlaying;
  final VoidCallback onTap;
  final bool showMenu;
  final String? heroTagPrefix;
  final String? playlistId;

  const SongListItem({
    super.key,
    required this.song,
    this.isPlaying,
    required this.onTap,
    this.showMenu = true,
    this.heroTagPrefix,
    this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final settings = ref.watch(settingsProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final selectionState = ref.watch(selectionProvider);
    final accent = AppTokens.accentOf(context, ref);

    final isSelected = selectionState.selectedFilenames.contains(song.filename);
    final isSuggestLess = userData.isSuggestLess(song.filename);
    final isFavorite = userData.isFavorite(song.filename);

    // Unique per list so the same song in two lists does not collide.
    final heroTag = heroTagPrefix != null
        ? '${heroTagPrefix}_${song.filename}'
        : 'list_art_${song.filename}_${key.toString()}';

    return ValueListenableBuilder<Song?>(
      valueListenable: audioManager.currentSongNotifier,
      builder: (context, currentSong, _) {
        final effectiveIsPlaying =
            isPlaying ?? (currentSong?.filename == song.filename);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
          child: AppListRow(
            accent: accent,
            isActive: isSelected || effectiveIsPlaying,
            isDimmed: isSuggestLess,
            strikeThrough: isSuggestLess,
            title: song.title,
            onTap: selectionState.isSelectionMode
                ? () => ref
                    .read(selectionProvider.notifier)
                    .toggleSelection(song.filename)
                : onTap,
            onLongPress: () {
              if (!selectionState.isSelectionMode) {
                ref
                    .read(selectionProvider.notifier)
                    .enterSelectionMode(song.filename);
                HapticFeedback.heavyImpact();
              } else {
                showSongOptionsMenu(context, ref, song.filename, song.title,
                    song: song, playlistId: playlistId);
              }
            },
            leading: _Artwork(
              song: song,
              heroTag: heroTag,
              isSelected: isSelected,
              isPlaying: effectiveIsPlaying,
              currentSong: currentSong,
              accent: accent,
              audioManager: audioManager,
              visualizerEnabled: settings.visualizerEnabled,
            ),
            subtitleWidget: Row(
              children: [
                Flexible(
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (settings.showSongDuration &&
                    song.duration != null &&
                    song.duration!.inSeconds > 0) ...[
                  const SizedBox(width: AppTokens.s2),
                  DurationBadge(
                    duration: song.duration,
                    isSubtle: true,
                    showIcon: false,
                  ),
                ],
              ],
            ),
            trailing: showMenu && !selectionState.isSelectionMode
                ? _Actions(
                    song: song,
                    isFavorite: isFavorite,
                    accent: accent,
                    playlistId: playlistId,
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final Song song;
  final String heroTag;
  final bool isSelected;
  final bool isPlaying;
  final Song? currentSong;
  final Color accent;
  final AudioPlayerManager audioManager;
  final bool visualizerEnabled;

  const _Artwork({
    required this.song,
    required this.heroTag,
    required this.isSelected,
    required this.isPlaying,
    required this.currentSong,
    required this.accent,
    required this.audioManager,
    required this.visualizerEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Hero(
          tag: heroTag,
          child: AnimatedScale(
            duration: AppTokens.dBase,
            scale: isSelected ? 0.85 : 1.0,
            child: AppRowArt(
              child: AlbumArtImage(
                url: song.coverUrl ?? '',
                filename: song.filename,
                width: AppTokens.artSize,
                height: AppTokens.artSize,
                fit: BoxFit.cover,
                memCacheWidth: 104,
                memCacheHeight: 104,
              ),
            ),
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.72),
                borderRadius: AppTokens.brSm,
              ),
              child: Icon(
                Icons.check_rounded,
                color: AppTokens.onAccent(accent),
                size: 26,
              ),
            ),
          )
        else if (isPlaying)
          Positioned.fill(
            child: StreamBuilder<PlayerState>(
              stream: audioManager.player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                if (!playing || currentSong?.filename != song.filename) {
                  return const SizedBox.shrink();
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: AppTokens.brSm,
                  ),
                  child: Center(
                    child: visualizerEnabled
                        ? const AudioVisualizer(
                            color: Colors.white,
                            width: 22,
                            height: 22,
                            isPlaying: true,
                          )
                        : const Icon(Icons.graphic_eq_rounded,
                            color: Colors.white, size: 22),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  final Song song;
  final bool isFavorite;
  final Color accent;
  final String? playlistId;

  const _Actions({
    required this.song,
    required this.isFavorite,
    required this.accent,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (song.playCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: AppTokens.accentWashAlpha),
              borderRadius: AppTokens.brPill,
            ),
            child: Text(
              '${song.playCount}',
              style: AppTokens.meta(context).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
          ),
        IconButton(
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFavorite ? accent : AppTokens.fgTertiary,
          ),
          onPressed: () =>
              ref.read(userDataProvider.notifier).toggleFavorite(song.filename),
        ),
        IconButton(
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.more_vert_rounded,
            color: AppTokens.fgSecondary,
          ),
          onPressed: () => showSongOptionsMenu(
            context,
            ref,
            song.filename,
            song.title,
            song: song,
            playlistId: playlistId,
          ),
        ),
      ],
    );
  }
}

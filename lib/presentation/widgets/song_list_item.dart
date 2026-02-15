import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/selection_provider.dart';
import 'album_art_image.dart';
import 'song_options_menu.dart';
import 'audio_visualizer.dart';
import 'duration_display.dart';

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
    final isSelected = selectionState.selectedFilenames.contains(song.filename);
    final isSuggestLess = userData.isSuggestLess(song.filename);
    final isFavorite = userData.isFavorite(song.filename);

    // Use a more robust unique tag for Hero
    final heroTag = heroTagPrefix != null
        ? '${heroTagPrefix}_${song.filename}'
        : 'list_art_${song.filename}_${key.toString()}';

    return ValueListenableBuilder<Song?>(
      valueListenable: audioManager.currentSongNotifier,
      builder: (context, currentSong, _) {
        final effectiveIsPlaying =
            isPlaying ?? (currentSong?.filename == song.filename);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : (effectiveIsPlaying
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.05)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
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
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Hero(
                          tag: heroTag,
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 300),
                            scale: isSelected ? 0.85 : 1.0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AlbumArtImage(
                                url: song.coverUrl ?? '',
                                filename: song.filename,
                                width: 52,
                                height: 52,
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.black,
                                size: 28,
                              ),
                            ),
                          )
                        else if (effectiveIsPlaying)
                          Positioned.fill(
                            child: StreamBuilder<PlayerState>(
                              stream: audioManager.player.playerStateStream,
                              builder: (context, snapshot) {
                                final playing = snapshot.data?.playing ?? false;
                                final shouldShowVisualizer = playing &&
                                    currentSong?.filename == song.filename;

                                if (!shouldShowVisualizer) {
                                  return const SizedBox.shrink();
                                }

                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Center(
                                    child: settings.visualizerEnabled
                                        ? const AudioVisualizer(
                                            color: Colors.white,
                                            width: 24,
                                            height: 24,
                                            isPlaying: true,
                                          )
                                        : const Icon(Icons.graphic_eq_rounded,
                                            color: Colors.white, size: 24),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.3,
                              color: effectiveIsPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : (isSuggestLess
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4)
                                      : Colors.white),
                              decoration: isSuggestLess
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(
                                            alpha: isSuggestLess ? 0.4 : 0.7),
                                  ),
                                ),
                              ),
                              if (settings.showSongDuration &&
                                  song.duration != null &&
                                  song.duration!.inSeconds > 0) ...[
                                const SizedBox(width: 8),
                                DurationBadge(
                                  duration: song.duration,
                                  isSubtle: true,
                                  showIcon: false,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showMenu && !selectionState.isSelectionMode) ...[
                      const SizedBox(width: 8),
                      if (song.playCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${song.playCount}",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.4),
                        ),
                        onPressed: () {
                          ref
                              .read(userDataProvider.notifier)
                              .toggleFavorite(song.filename);
                        },
                        iconSize: 20,
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () {
                          showSongOptionsMenu(
                              context, ref, song.filename, song.title,
                              song: song, playlistId: playlistId);
                        },
                        iconSize: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

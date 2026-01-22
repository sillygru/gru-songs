import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import 'gru_image.dart';
import 'song_options_menu.dart';

class SongListItem extends ConsumerWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final bool showMenu;

  const SongListItem({
    super.key,
    required this.song,
    this.isPlaying = false,
    required this.onTap,
    this.showMenu = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = ref.watch(userDataProvider);
    final isSuggestLess = userData.isSuggestLess(song.filename);
    final isFavorite = userData.isFavorite(song.filename);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: isPlaying
            ? Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.5),
                width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: showMenu
              ? () {
                  showSongOptionsMenu(context, ref, song.filename, song.title,
                      song: song);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Stack(
                  children: [
                    Hero(
                      tag: 'list_art_${song.filename}_${key.toString()}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GruImage(
                          url: song.coverUrl ?? '',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.music_note),
                          ),
                        ),
                      ),
                    ),
                    if (isPlaying)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(Icons.graphic_eq,
                                color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isPlaying
                                    ? Theme.of(context).colorScheme.primary
                                    : (isSuggestLess
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.5)
                                        : null),
                                decoration: isSuggestLess
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (isFavorite) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.favorite,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: isSuggestLess ? 0.5 : 1.0),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showMenu) ...[
                  const SizedBox(width: 8),
                  if (song.playCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${song.playCount}",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      showSongOptionsMenu(
                          context, ref, song.filename, song.title,
                          song: song);
                    },
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

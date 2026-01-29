import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/search_result.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import 'album_art_image.dart';
import 'lyrics_match_widget.dart';
import 'song_options_menu.dart';

/// Widget for displaying a search result item
class SearchResultItem extends ConsumerWidget {
  final SearchResult result;
  final String searchQuery;
  final VoidCallback onTap;
  final String? heroTagPrefix;

  const SearchResultItem({
    super.key,
    required this.result,
    required this.searchQuery,
    required this.onTap,
    this.heroTagPrefix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = result.song;
    final userData = ref.watch(userDataProvider);
    final isSuggestLess = userData.isSuggestLess(song.filename);
    final isFavorite = userData.isFavorite(song.filename);

    final heroTag = heroTagPrefix != null
        ? '${heroTagPrefix}_${song.filename}'
        : 'search_result_${song.filename}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: () {
            showSongOptionsMenu(
              context,
              ref,
              song.filename,
              song.title,
              song: song,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: heroTag,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AlbumArtImage(
                          url: song.coverUrl ?? '',
                          filename: song.filename,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          memCacheWidth: 112,
                          memCacheHeight: 112,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(context, isSuggestLess),
                          const SizedBox(height: 4),
                          _buildSubtitle(context, isSuggestLess),
                          if (result.hasLyricsMatch) ...[
                            const SizedBox(height: 4),
                            LyricsMatchWidget(
                              lyricsMatch: result.lyricsMatch!,
                              searchQuery: searchQuery,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isFavorite) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.favorite,
                        size: 18,
                        color: Colors.red.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isSuggestLess) {
    final theme = Theme.of(context);
    final titleSpans = _buildHighlightedText(
      result.song.title,
      searchQuery,
      TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: isSuggestLess
            ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
            : theme.colorScheme.onSurface,
        decoration: isSuggestLess ? TextDecoration.lineThrough : null,
      ),
    );

    return RichText(
      text: TextSpan(children: titleSpans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSubtitle(BuildContext context, bool isSuggestLess) {
    final theme = Theme.of(context);
    final subtitle = '${result.song.artist} • ${result.song.album}';
    final subtitleSpans = _buildHighlightedText(
      subtitle,
      searchQuery,
      TextStyle(
        fontSize: 13,
        color: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: isSuggestLess ? 0.5 : 1.0,
        ),
      ),
    );

    return RichText(
      text: TextSpan(children: subtitleSpans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Builds text spans with the search query highlighted in bold
  List<TextSpan> _buildHighlightedText(
    String text,
    String query,
    TextStyle baseStyle,
  ) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase().trim();

    if (lowerQuery.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    int currentIndex = 0;
    int matchIndex = lowerText.indexOf(lowerQuery, currentIndex);

    while (matchIndex != -1) {
      // Add text before match
      if (matchIndex > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, matchIndex),
          style: baseStyle,
        ));
      }

      // Add highlighted match
      final matchEnd = matchIndex + lowerQuery.length;
      spans.add(TextSpan(
        text: text.substring(matchIndex, matchEnd),
        style: baseStyle.copyWith(
          fontWeight: FontWeight.bold,
          color: baseStyle.color,
        ),
      ));

      currentIndex = matchEnd;
      matchIndex = lowerText.indexOf(lowerQuery, currentIndex);
    }

    // Add remaining text
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}

/// Widget for displaying artist search results
class ArtistSearchResultItem extends StatelessWidget {
  final String artistName;
  final List<Song> songs;
  final VoidCallback onTap;

  const ArtistSearchResultItem({
    super.key,
    required this.artistName,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Hero(
                  tag: 'artist_$artistName',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: songs.isNotEmpty
                        ? AlbumArtImage(
                            url: songs.first.coverUrl ?? '',
                            filename: songs.first.filename,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            memCacheWidth: 112,
                            memCacheHeight: 112,
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.person,
                              size: 32,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${songs.length} song${songs.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget for displaying album search results
class AlbumSearchResultItem extends StatelessWidget {
  final String albumName;
  final String artistName;
  final List<Song> songs;
  final VoidCallback onTap;

  const AlbumSearchResultItem({
    super.key,
    required this.albumName,
    required this.artistName,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Hero(
                  tag: 'album_${albumName}_$artistName',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: songs.isNotEmpty
                        ? AlbumArtImage(
                            url: songs.first.coverUrl ?? '',
                            filename: songs.first.filename,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            memCacheWidth: 112,
                            memCacheHeight: 112,
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.album,
                              size: 32,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        albumName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artistName,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${songs.length} song${songs.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

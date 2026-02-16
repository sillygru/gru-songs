import 'package:flutter/material.dart';
import '../../domain/models/search_result.dart';

/// Widget that displays a lyrics match with the matched text in bold
///
/// Example: If searching for "let you" and the lyric is "let you down",
/// displays: contains "**let you** down"
class LyricsMatchWidget extends StatelessWidget {
  final LyricsMatch lyricsMatch;
  final String searchQuery;

  const LyricsMatchWidget({
    super.key,
    required this.lyricsMatch,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textSpans = _buildTextSpans();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: RichText(
              text: TextSpan(
                children: textSpans,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the text spans with the matched portion in bold
  List<TextSpan> _buildTextSpans() {
    final spans = <TextSpan>[];
    final fullLine = lyricsMatch.fullLine;
    final query = searchQuery.toLowerCase().trim();

    if (query.isEmpty) {
      spans.add(TextSpan(text: 'contains "$fullLine"'));
      return spans;
    }

    // Find the match position (case-insensitive)
    final lowerLine = fullLine.toLowerCase();
    final matchIndex = lowerLine.indexOf(query);

    if (matchIndex == -1) {
      // No match found, just show the full line
      spans.add(TextSpan(text: 'contains "$fullLine"'));
      return spans;
    }

    // Build the spans: prefix + bold match + suffix
    final matchEnd = matchIndex + query.length;

    // "contains " prefix
    spans.add(const TextSpan(text: 'contains "'));

    // Text before the match
    if (matchIndex > 0) {
      spans.add(TextSpan(text: fullLine.substring(0, matchIndex)));
    }

    // The matched text in bold
    spans.add(TextSpan(
      text: fullLine.substring(matchIndex, matchEnd),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));

    // Text after the match
    if (matchEnd < fullLine.length) {
      spans.add(TextSpan(text: fullLine.substring(matchEnd)));
    }

    // Closing quote
    spans.add(const TextSpan(text: '"'));

    return spans;
  }
}

/// A more compact version of the lyrics match widget for list items
class CompactLyricsMatchWidget extends StatelessWidget {
  final LyricsMatch lyricsMatch;
  final String searchQuery;

  const CompactLyricsMatchWidget({
    super.key,
    required this.lyricsMatch,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = _buildDisplayText();

    return Container(
      margin: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 12,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 11,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildDisplayText() {
    final fullLine = lyricsMatch.fullLine;
    final query = searchQuery.toLowerCase().trim();

    if (query.isEmpty) {
      return 'contains "$fullLine"';
    }

    final lowerLine = fullLine.toLowerCase();
    final matchIndex = lowerLine.indexOf(query);

    if (matchIndex == -1) {
      return 'contains "$fullLine"';
    }

    // Truncate if too long
    const maxLength = 40;
    String displayLine = fullLine;
    if (displayLine.length > maxLength) {
      // Try to center the match in the truncated view
      final matchCenter = matchIndex + query.length ~/ 2;
      final start =
          (matchCenter - maxLength ~/ 2).clamp(0, fullLine.length - maxLength);
      final end = (start + maxLength).clamp(0, fullLine.length);
      displayLine = fullLine.substring(start, end);
      if (start > 0) displayLine = '...$displayLine';
      if (end < fullLine.length) displayLine = '$displayLine...';
    }

    return 'contains "$displayLine"';
  }
}

/// Widget to show when a song has lyrics available (for search results)
class LyricsAvailableIndicator extends StatelessWidget {
  const LyricsAvailableIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Lyrics available',
      child: Icon(
        Icons.lyrics_outlined,
        size: 16,
        color: theme.colorScheme.primary.withValues(alpha: 0.6),
      ),
    );
  }
}

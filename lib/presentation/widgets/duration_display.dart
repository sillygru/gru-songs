import 'package:flutter/material.dart';
import '../../models/song.dart';

/// Utility class for formatting durations
class DurationFormatter {
  /// Formats a duration as MM:SS or HH:MM:SS
  static String format(Duration? duration) {
    if (duration == null || duration.inSeconds == 0) {
      return '--:--';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Formats a duration as a compact string (e.g., "3m 42s" or "1h 23m")
  static String formatCompact(Duration? duration) {
    if (duration == null || duration.inSeconds == 0) {
      return '';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Formats total duration for a list of songs
  static String formatTotal(List<Song> songs) {
    final totalDuration = _calculateTotalDuration(songs);
    return format(totalDuration);
  }

  /// Formats total duration as compact string
  static String formatTotalCompact(List<Song> songs) {
    final totalDuration = _calculateTotalDuration(songs);
    return formatCompact(totalDuration);
  }

  /// Calculates total duration from a list of songs
  static Duration _calculateTotalDuration(List<Song> songs) {
    int totalSeconds = 0;
    for (final song in songs) {
      if (song.duration != null) {
        totalSeconds += song.duration!.inSeconds;
      }
    }
    return Duration(seconds: totalSeconds);
  }

  /// Gets the count of songs with valid durations
  static int getSongsWithDurationCount(List<Song> songs) {
    return songs
        .where((s) => s.duration != null && s.duration!.inSeconds > 0)
        .length;
  }
}

/// Widget to display duration on a song list item
class SongDurationDisplay extends StatelessWidget {
  final Duration? duration;
  final TextStyle? style;

  const SongDurationDisplay({
    super.key,
    this.duration,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = DurationFormatter.format(duration);

    return Text(
      displayText,
      style: style ??
          TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
    );
  }
}

/// Widget to display duration for a folder/playlist/album
class CollectionDurationDisplay extends StatelessWidget {
  final List<Song> songs;
  final bool showSongCount;
  final TextStyle? style;
  final bool compact;

  const CollectionDurationDisplay({
    super.key,
    required this.songs,
    this.showSongCount = true,
    this.style,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationText = compact
        ? DurationFormatter.formatTotalCompact(songs)
        : DurationFormatter.formatTotal(songs);

    String displayText;
    if (showSongCount) {
      final songsWithDuration =
          DurationFormatter.getSongsWithDurationCount(songs);
      final totalSongs = songs.length;

      if (songsWithDuration < totalSongs) {
        displayText = '$totalSongs songs • $durationText';
      } else {
        displayText = '$totalSongs songs • $durationText';
      }
    } else {
      displayText = durationText;
    }

    return Text(
      displayText,
      style: style ??
          TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Compact duration badge for small spaces
class DurationBadge extends StatelessWidget {
  final Duration? duration;
  final bool showIcon;
  final bool isSubtle;

  const DurationBadge({
    super.key,
    this.duration,
    this.showIcon = true,
    this.isSubtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = DurationFormatter.format(duration);

    if (duration == null || duration!.inSeconds == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSubtle
            ? Colors.transparent
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: isSubtle
            ? Border.all(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                width: 0.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              Icons.schedule,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 2),
          ],
          Text(
            displayText,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

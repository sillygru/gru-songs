import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../tokens/app_tokens.dart';

/// "12 tracks · 48:20" — the one-line summary shown under a collection card.
/// Lives here next to [DurationFormatter] so artists, albums, folders and
/// playlists all describe themselves the same way.
String collectionSummary(List<Song> songs) {
  final count = '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}';
  final total = songs.fold<Duration>(
    Duration.zero,
    (sum, song) => sum + (song.duration ?? Duration.zero),
  );
  if (total == Duration.zero) return count;
  return '$count · ${DurationFormatter.format(total)}';
}

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

  /// Formats remaining time for a queue (e.g., "23m left", "1h 14m left", "45s left")
  static String formatRemaining(int totalSeconds) {
    if (totalSeconds <= 0) return '';
    final h = Duration(seconds: totalSeconds).inHours;
    final m = Duration(seconds: totalSeconds).inMinutes.remainder(60);
    final s = Duration(seconds: totalSeconds).inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m left';
    if (m > 0) return '${m}m ${s}s left';
    return '${s}s left';
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
      // Subtle badges are set apart by a faint fill, not by a hairline outline.
      decoration: BoxDecoration(
        color: isSubtle
            ? AppTokens.surface(2)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppTokens.brPill,
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

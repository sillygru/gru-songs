import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../tokens/player_tokens.dart';
import '../widgets/album_art_image.dart' show StaticAlbumArtImage;
import '../widgets/audio_visualizer.dart';
import '../widgets/duration_display.dart' show DurationFormatter;

/// The one track row used everywhere in the player — Up Next, the played
/// section above the current track, and the expanded contents of a history
/// snapshot. Using a single row across all three lists is most of what makes
/// the panes feel like one screen rather than three.
class PlayerTrackRow extends StatelessWidget {
  final Song song;

  /// The currently playing track: accent-tinted, with a visualizer or bars.
  final bool isCurrent;

  /// Already played — dimmed back.
  final bool isPlayed;

  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onIndicatorTap;

  /// Shows the animated bars on the current row (settings.animatedSoundWaveEnabled).
  final bool showAnimatedWave;

  /// Trailing slot — a reorder drag handle, an overflow button, or nothing.
  final Widget? trailing;

  /// Ordinal shown in place of the artwork badge, used by history listings.
  final int? index;

  const PlayerTrackRow({
    super.key,
    required this.song,
    required this.accent,
    this.isCurrent = false,
    this.isPlayed = false,
    this.onTap,
    this.onIndicatorTap,
    this.showAnimatedWave = false,
    this.trailing,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: PlayerTokens.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: PlayerTokens.s4),
      // No outline — the current row is marked by an accent wash and accent
      // title text, not by a border drawn around it.
      decoration: isCurrent
          ? BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: PlayerTokens.brMd,
            )
          : null,
      child: Row(
        children: [
          _buildArtwork(),
          const SizedBox(width: PlayerTokens.s3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PlayerTokens.trackTitle(context).copyWith(
                    color: isCurrent ? accent : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PlayerTokens.trackSubtitle(context),
                ),
              ],
            ),
          ),
          if (song.duration != null) ...[
            const SizedBox(width: PlayerTokens.s2),
            Text(
              DurationFormatter.format(song.duration),
              style: PlayerTokens.meta(context),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: PlayerTokens.s1),
            trailing!,
          ],
        ],
      ),
    );

    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: PlayerTokens.brMd,
        child: row,
      ),
    );

    if (!isPlayed) return tappable;
    return Opacity(opacity: PlayerTokens.aPlayed, child: tappable);
  }

  Widget _buildArtwork() {
    final art = ClipRRect(
      borderRadius: PlayerTokens.brSm,
      child: SizedBox(
        width: PlayerTokens.artSize,
        height: PlayerTokens.artSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StaticAlbumArtImage(
              url: song.coverUrl ?? '',
              filename: song.filename,
              width: PlayerTokens.artSize,
              height: PlayerTokens.artSize,
              fit: BoxFit.cover,
            ),
            if (isCurrent)
              GestureDetector(
                onTap: onIndicatorTap,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.42),
                  child: Center(
                    child: showAnimatedWave
                        ? const AudioVisualizer(
                            width: 18,
                            height: 18,
                            color: Colors.white,
                            isPlaying: true,
                          )
                        : const Icon(
                            Icons.graphic_eq_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (index == null || isCurrent) return art;

    return SizedBox(
      width: PlayerTokens.artSize,
      height: PlayerTokens.artSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          art,
          Positioned(
            left: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: PlayerTokens.brPill,
              ),
              child: Text(
                '${index! + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

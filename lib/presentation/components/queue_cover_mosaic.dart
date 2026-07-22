import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../tokens/player_tokens.dart';
import '../widgets/album_art_image.dart' show StaticAlbumArtImage;

/// A square identity thumbnail for a queue: the first few covers tiled into one
/// tile, so a saved queue is recognisable at a glance instead of reading as one
/// more line of text.
///
/// The tiling follows the number of covers actually available — one cover fills
/// the square, two split it, three use a large left tile, four make a 2x2 grid.
/// With nothing to show it falls back to a deterministic gradient seeded from
/// [seed], so the same queue keeps the same colours between sessions.
class QueueCoverMosaic extends StatelessWidget {
  final List<Song> songs;
  final double size;
  final Color accent;

  /// Stable string (a snapshot id) used to pick the placeholder gradient.
  final String seed;

  const QueueCoverMosaic({
    super.key,
    required this.songs,
    required this.accent,
    required this.seed,
    this.size = 60,
  });

  static const double _gap = 1.5;

  @override
  Widget build(BuildContext context) {
    final covers = songs
        .where((song) => (song.coverUrl ?? '').isNotEmpty)
        .take(4)
        .toList();

    return ClipRRect(
      borderRadius: PlayerTokens.brSm,
      child: SizedBox(
        width: size,
        height: size,
        child: Container(
          // Shows through the gaps between tiles and behind missing artwork.
          color: Colors.white.withValues(alpha: 0.06),
          child: covers.isEmpty ? _buildPlaceholder() : _buildTiles(covers),
        ),
      ),
    );
  }

  Widget _buildTiles(List<Song> covers) {
    switch (covers.length) {
      case 1:
        return _cover(covers[0], size);
      case 2:
        return Row(
          children: [
            Expanded(child: _cover(covers[0], size / 2)),
            const SizedBox(width: _gap),
            Expanded(child: _cover(covers[1], size / 2)),
          ],
        );
      case 3:
        return Row(
          children: [
            Expanded(child: _cover(covers[0], size / 2)),
            const SizedBox(width: _gap),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _cover(covers[1], size / 2)),
                  const SizedBox(height: _gap),
                  Expanded(child: _cover(covers[2], size / 2)),
                ],
              ),
            ),
          ],
        );
      default:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cover(covers[0], size / 2)),
                  const SizedBox(width: _gap),
                  Expanded(child: _cover(covers[1], size / 2)),
                ],
              ),
            ),
            const SizedBox(height: _gap),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cover(covers[2], size / 2)),
                  const SizedBox(width: _gap),
                  Expanded(child: _cover(covers[3], size / 2)),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _cover(Song song, double extent) {
    return StaticAlbumArtImage(
      url: song.coverUrl ?? '',
      filename: song.filename,
      width: extent,
      height: extent,
      fit: BoxFit.cover,
    );
  }

  Widget _buildPlaceholder() {
    final hue = (seed.hashCode.abs() % 360).toDouble();
    final base = HSLColor.fromAHSL(1, hue, 0.34, 0.42).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, accent, 0.25)!.withValues(alpha: 0.85),
            base.withValues(alpha: 0.35),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: size * 0.4,
          color: Colors.white.withValues(alpha: PlayerTokens.aSecondary),
        ),
      ),
    );
  }
}

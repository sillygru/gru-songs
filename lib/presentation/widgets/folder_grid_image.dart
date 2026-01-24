import 'package:flutter/material.dart';
import '../../models/song.dart';
import 'gru_image.dart';

class FolderGridImage extends StatelessWidget {
  final List<Song> songs;
  final double size;

  const FolderGridImage({
    super.key,
    required this.songs,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    // Get unique covers
    final uniqueCovers = <String>{};
    final List<String> covers = [];
    for (var song in songs) {
      if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
        if (uniqueCovers.add(song.coverUrl!)) {
          covers.add(song.coverUrl!);
          if (covers.length >= 4) break;
        }
      }
    }

    if (covers.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.folder, size: size * 0.6, color: Colors.amber),
      );
    }

    if (covers.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GruImage(
          url: covers[0],
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: Container(
            color: Colors.amber.withValues(alpha: 0.2),
            child: const Icon(Icons.folder, color: Colors.amber),
          ),
        ),
      );
    }

    // 2, 3, or 4 covers
    final int displayCount = covers.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: GruImage(
                      url: covers[0],
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: GruImage(
                      url: covers[1 % displayCount],
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: GruImage(
                      url: covers[2 % displayCount],
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: GruImage(
                      url: covers[3 % displayCount],
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

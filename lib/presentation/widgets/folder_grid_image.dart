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
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            // If we have fewer than 4, we cycle through them to fill the grid
            final url = covers[index % displayCount];
            return GruImage(
              url: url,
              width: size / 2,
              height: size / 2,
              fit: BoxFit.cover,
            );
          },
        ),
      ),
    );
  }
}

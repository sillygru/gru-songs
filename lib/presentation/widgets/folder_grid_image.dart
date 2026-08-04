import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import 'album_art_image.dart';
import '../tokens/app_tokens.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class FolderGridImage extends StatelessWidget {
  final List<Song> songs;
  final double size;
  final bool isGridItem;

  const FolderGridImage({
    super.key,
    required this.songs,
    this.size = 48,
    this.isGridItem = false,
  });

  /// Resolves a cover URL to a local path and its file size.
  /// Returns null if the file doesn't exist or the URL isn't a local path.
  /// Single stat call per file: existence + size in one syscall.
  static ({String path, int size})? _resolveCover(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (!trimmed.startsWith('/') &&
        !trimmed.startsWith('file://') &&
        !trimmed.startsWith('C:\\')) {
      return null;
    }
    try {
      final path = trimmed.startsWith('file://')
          ? Uri.parse(trimmed).toFilePath()
          : trimmed;
      final file = File(path);
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return (path: path, size: stat.size);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueCovers = <String>{};
    final List<String> covers = [];
    int? firstSize;
    bool allSameSize = true;

    for (final song in songs) {
      if (covers.length >= 4) break;
      final result = _resolveCover(song.coverUrl);
      if (result == null || !uniqueCovers.add(result.path)) continue;

      // Track file size as we go to detect duplicates (same image extracted
      // from different songs in the same album).
      if (allSameSize) {
        if (firstSize == null) {
          firstSize = result.size;
        } else if (result.size != firstSize) {
          allSameSize = false;
        }
      }

      covers.add(result.path);
    }

    // If all unique covers have the same file size, they're the same image
    // extracted from different songs — show a single full cover instead of
    // repeating it in a grid.
    if (covers.length >= 2 && allSameSize) {
      covers.removeRange(1, covers.length);
    }

    if (covers.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTokens.warning.withValues(alpha: 0.2),
          borderRadius: AppTokens.brSm,
        ),
        child: AppIcon(
          AppIcons.folder,
          size: size * 0.6,
          color: AppTokens.warning,
        ),
      );
    }

    if (covers.length == 1) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: AlbumArtImage(
          url: covers[0],
          filename: covers[0],
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: isGridItem ? (size * 4).toInt() : null,
          memCacheHeight: isGridItem ? (size * 4).toInt() : null,
        ),
      );
    }

    const double gap = 1.0;

    if (covers.length == 2) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: SizedBox(
          width: size,
          height: size,
          child: Row(
            children: [
              Expanded(
                child: AlbumArtImage(
                  url: covers[0],
                  filename: covers[0],
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                  memCacheHeight: isGridItem ? (size * 4).toInt() : null,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: AlbumArtImage(
                  url: covers[1],
                  filename: covers[1],
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                  memCacheHeight: isGridItem ? (size * 4).toInt() : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (covers.length == 3) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: SizedBox(
          width: size,
          height: size,
          child: Row(
            children: [
              Expanded(
                child: AlbumArtImage(
                  url: covers[0],
                  filename: covers[0],
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                  memCacheHeight: isGridItem ? (size * 4).toInt() : null,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: AlbumArtImage(
                        url: covers[1],
                        filename: covers[1],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                        memCacheHeight: isGridItem ? (size * 2).toInt() : null,
                      ),
                    ),
                    const SizedBox(height: gap),
                    Expanded(
                      child: AlbumArtImage(
                        url: covers[2],
                        filename: covers[2],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                        memCacheHeight: isGridItem ? (size * 2).toInt() : null,
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

    return ClipRRect(
      borderRadius: AppTokens.brSm,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: AlbumArtImage(
                      url: covers[0],
                      filename: covers[0],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                      memCacheHeight: isGridItem ? (size * 2).toInt() : null,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: AlbumArtImage(
                      url: covers[1],
                      filename: covers[1],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                      memCacheHeight: isGridItem ? (size * 2).toInt() : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: AlbumArtImage(
                      url: covers[2],
                      filename: covers[2],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                      memCacheHeight: isGridItem ? (size * 2).toInt() : null,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: AlbumArtImage(
                      url: covers[3],
                      filename: covers[3],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: isGridItem ? (size * 2).toInt() : null,
                      memCacheHeight: isGridItem ? (size * 2).toInt() : null,
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

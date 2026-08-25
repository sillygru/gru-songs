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

  /// Resolves a cover URL to a normalized local path.
  /// Returns null if the URL is empty or not a local path.
  static String? _resolveCover(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('/') &&
        !trimmed.startsWith('file://') &&
        !trimmed.startsWith('C:\\')) {
      return null;
    }
    try {
      return trimmed.startsWith('file://')
          ? Uri.parse(trimmed).toFilePath()
          : trimmed;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueCovers = <String>{};
    final coverEntries = <({String url, String filename})>[];

    for (final song in songs) {
      if (coverEntries.length >= 4) break;
      final path = _resolveCover(song.coverUrl);
      if (path == null || !uniqueCovers.add(path)) continue;
      coverEntries.add((url: path, filename: song.filename));
    }

    if (coverEntries.isEmpty) {
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

    if (coverEntries.length == 1) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: AlbumArtImage(
          url: coverEntries[0].url,
          filename: coverEntries[0].filename,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: isGridItem ? (size * 4).toInt() : null,
          memCacheHeight: isGridItem ? (size * 4).toInt() : null,
        ),
      );
    }

    const double gap = 1.0;

    if (coverEntries.length == 2) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: SizedBox(
          width: size,
          height: size,
          child: Row(
            children: [
              Expanded(
                child: AlbumArtImage(
                  url: coverEntries[0].url,
                  filename: coverEntries[0].filename,
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
                  url: coverEntries[1].url,
                  filename: coverEntries[1].filename,
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

    if (coverEntries.length == 3) {
      return ClipRRect(
        borderRadius: AppTokens.brSm,
        child: SizedBox(
          width: size,
          height: size,
          child: Row(
            children: [
              Expanded(
                child: AlbumArtImage(
                  url: coverEntries[0].url,
                  filename: coverEntries[0].filename,
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
                        url: coverEntries[1].url,
                        filename: coverEntries[1].filename,
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
                        url: coverEntries[2].url,
                        filename: coverEntries[2].filename,
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
                      url: coverEntries[0].url,
                      filename: coverEntries[0].filename,
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
                      url: coverEntries[1].url,
                      filename: coverEntries[1].filename,
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
                      url: coverEntries[2].url,
                      filename: coverEntries[2].filename,
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
                      url: coverEntries[3].url,
                      filename: coverEntries[3].filename,
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

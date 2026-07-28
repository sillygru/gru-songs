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

  static bool _isValidCoverUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    if (trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('C:\\')) {
      try {
        final path = trimmed.startsWith('file://')
            ? Uri.parse(trimmed).toFilePath()
            : trimmed;
        return File(path).existsSync();
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final uniqueCovers = <String>{};
    final List<String> covers = [];
    for (final song in songs) {
      final url = song.coverUrl;
      if (_isValidCoverUrl(url)) {
        if (uniqueCovers.add(url!)) {
          covers.add(url);
          if (covers.length >= 4) break;
        }
      }
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

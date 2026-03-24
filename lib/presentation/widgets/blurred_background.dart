import 'dart:io';
import 'package:flutter/material.dart';
import 'album_art_image.dart';
import '../../services/cache_service.dart';

class BlurredBackground extends StatelessWidget {
  final String url;
  final String? filename;
  final double sigma;
  final List<Color>? gradientColors;

  const BlurredBackground({
    super.key,
    required this.url,
    this.filename,
    this.sigma = 40,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<File>(
              future: filename != null
                  ? CacheService.instance.getBlurredCacheFile(filename!)
                  : Future.error('No filename'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  final hasCache =
                      snapshot.hasData && snapshot.data!.existsSync();

                  if (hasCache) {
                    return Image.file(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                    );
                  }
                }

                return AlbumArtImage(
                  url: url,
                  filename: filename,
                  fit: BoxFit.cover,
                  memCacheWidth: 60,
                  memCacheHeight: 60,
                  filterQuality: FilterQuality.low,
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors ??
                      [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

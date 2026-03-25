import 'dart:io';
import 'package:flutter/material.dart';
import 'album_art_image.dart';
import '../../services/cache_service.dart';

class BlurredBackground extends StatefulWidget {
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
  State<BlurredBackground> createState() => _BlurredBackgroundState();
}

class _BlurredBackgroundState extends State<BlurredBackground> {
  Future<File>? _blurFuture;
  String? _lastFilename;

  @override
  void initState() {
    super.initState();
    _updateFuture();
  }

  @override
  void didUpdateWidget(BlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filename != oldWidget.filename) {
      _updateFuture();
    }
  }

  void _updateFuture() {
    if (widget.filename != null && widget.filename != _lastFilename) {
      _lastFilename = widget.filename;
      _blurFuture = CacheService.instance.getBlurredCacheFile(widget.filename!);
    } else if (widget.filename == null) {
      _lastFilename = null;
      _blurFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // Base layer: Low-res album art (always there as fallback)
          Positioned.fill(
            child: AlbumArtImage(
              url: widget.url,
              filename: widget.filename,
              fit: BoxFit.cover,
              memCacheWidth: 80,
              memCacheHeight: 80,
              filterQuality: FilterQuality.low,
            ),
          ),

          // Blurred layer: Fades in when ready
          if (_blurFuture != null)
            Positioned.fill(
              child: FutureBuilder<File>(
                future: _blurFuture,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  final bool isReady =
                      snapshot.connectionState == ConnectionState.done &&
                          file != null &&
                          file.existsSync();

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: isReady ? 1.0 : 0.0,
                    curve: Curves.easeIn,
                    child: isReady
                        ? Image.file(
                            file,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                          )
                        : const SizedBox.shrink(),
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
                  colors: widget.gradientColors ??
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

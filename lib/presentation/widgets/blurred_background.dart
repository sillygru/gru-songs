import 'dart:io';
import 'package:flutter/material.dart';
import 'album_art_image.dart';
import '../../services/cache_service.dart';
import '../../services/ffmpeg_service.dart';

class BlurredBackground extends StatefulWidget {
  final String url;
  final String? filename;
  final List<Color>? gradientColors;

  const BlurredBackground({
    super.key,
    required this.url,
    this.filename,
    this.gradientColors,
  });

  @override
  State<BlurredBackground> createState() => _BlurredBackgroundState();
}

class _BlurredBackgroundState extends State<BlurredBackground> {
  File? _blurFile;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _updateBlurFile();
  }

  @override
  void didUpdateWidget(BlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filename != oldWidget.filename) {
      _updateBlurFile();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _updateBlurFile() async {
    _blurFile = null;

    final filename = widget.filename;
    if (filename == null) {
      if (mounted) setState(() {});
      return;
    }

    final token = ++_requestToken;
    final blurFile = await CacheService.instance.getBlurredCacheFile(filename);
    if (!mounted || token != _requestToken) return;

    _blurFile = blurFile;
    if (await blurFile.exists()) {
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() {});

    final coverUrl = widget.url;
    if (coverUrl.isEmpty) return;

    final success = await FFmpegService().generateBlurredImage(
      inputPath: coverUrl,
      outputPath: blurFile.path,
    );

    if (!mounted || token != _requestToken) return;

    if (success && await blurFile.exists()) {
      setState(() {
        _blurFile = blurFile;
      });
    }
  }

  bool get _hasBlurredBackground =>
      _blurFile != null && _blurFile!.existsSync();

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

          // Blurred layer: fades in once the cache file exists
          if (_hasBlurredBackground)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: 1.0,
                curve: Curves.easeIn,
                child: Image.file(
                  _blurFile!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
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

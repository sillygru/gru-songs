import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'album_art_image.dart';
import '../../services/cache_service.dart';
import '../../services/cover_refresh_service.dart';
import '../../services/ffmpeg_service.dart';

class BlurredBackground extends StatefulWidget {
  final String url;
  final String? filename;
  final List<Color>? gradientColors;
  final bool slowSpin;

  const BlurredBackground({
    super.key,
    required this.url,
    this.filename,
    this.gradientColors,
    this.slowSpin = false,
  });

  @override
  State<BlurredBackground> createState() => _BlurredBackgroundState();
}

class _BlurredBackgroundState extends State<BlurredBackground>
    with SingleTickerProviderStateMixin {
  File? _blurFile;
  int _requestToken = 0;
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    );
    if (widget.slowSpin) {
      _spinController.repeat();
    }
    _updateBlurFile();
  }

  @override
  void didUpdateWidget(BlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filename != oldWidget.filename || widget.url != oldWidget.url) {
      _updateBlurFile();
    }
    if (widget.slowSpin != oldWidget.slowSpin) {
      if (widget.slowSpin) {
        _spinController.repeat();
      } else {
        _spinController.stop();
      }
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
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

    var coverUrl = widget.url;
    final needsCoverRefresh = coverUrl.isEmpty ||
        (!coverUrl.startsWith('content://') &&
            !coverUrl.startsWith('http://') &&
            !coverUrl.startsWith('https://') &&
            !await File(_normalizeFilePath(coverUrl)).exists());
    if (needsCoverRefresh && filename.isNotEmpty) {
      coverUrl =
          await CoverRefreshService.instance.ensureCoverForSong(filename) ??
              coverUrl;
    }
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

  String _normalizeFilePath(String path) {
    if (path.startsWith('file://')) {
      try {
        return Uri.parse(path).toFilePath();
      } catch (_) {}
    }
    return path;
  }

  Widget _buildImageLayers({double? squareSize}) {
    final child = Stack(
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
      ],
    );

    if (squareSize != null) {
      return SizedBox(width: squareSize, height: squareSize, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Slow spinning blur layers — displayed as a large square so
          // no rectangular borders are visible during rotation.
          if (widget.slowSpin)
            LayoutBuilder(
              builder: (context, constraints) {
                // Square big enough that its corners, when rotated, stay
                // outside the viewport on every device.
                final squareSize =
                    math.max(constraints.maxWidth, constraints.maxHeight) *
                        math.sqrt2;
                return OverflowBox(
                  maxWidth: squareSize,
                  maxHeight: squareSize,
                  alignment: Alignment.center,
                  child: AnimatedBuilder(
                    animation: _spinController,
                    builder: (context, child) {
                      final angle = _spinController.value * 2 * math.pi;
                      final breathe =
                          math.sin(_spinController.value * 2 * math.pi);
                      final scale = 1.0 + 0.015 * breathe;
                      return Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: Transform.rotate(
                          angle: angle,
                          alignment: Alignment.center,
                          child: child,
                        ),
                      );
                    },
                    child: _buildImageLayers(squareSize: squareSize),
                  ),
                );
              },
            )
          else
            _buildImageLayers(),

          // Static gradient overlay stays fixed while blur spins beneath
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

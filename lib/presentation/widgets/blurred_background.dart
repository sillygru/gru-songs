import 'dart:io';
import 'dart:async';
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
  File? _blurFile;
  Timer? _pollTimer;
  String? _lastFilename;
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
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateBlurFile() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastFilename = widget.filename;
    _blurFile = null;

    final filename = widget.filename;
    if (filename == null) {
      if (mounted) setState(() {});
      return;
    }

    final token = ++_requestToken;
    final blurFile = await CacheService.instance.getBlurredCacheFile(filename);
    if (!mounted || token != _requestToken || filename != _lastFilename) {
      return;
    }

    _blurFile = blurFile;
    if (await blurFile.exists()) {
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() {});

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || token != _requestToken || filename != _lastFilename) {
        _pollTimer?.cancel();
        return;
      }

      if (await blurFile.exists()) {
        _pollTimer?.cancel();
        if (mounted && token == _requestToken) {
          setState(() {
            _blurFile = blurFile;
          });
        }
      }
    });
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

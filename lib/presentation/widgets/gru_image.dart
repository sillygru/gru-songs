import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/cache_service.dart';

class GruImage extends StatefulWidget {
  final String url;
  final String? filename;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const GruImage({
    super.key,
    required this.url,
    this.filename,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.placeholder,
    this.errorWidget,
    this.cacheWidth,
    this.cacheHeight,
  });

  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<GruImage> createState() => _GruImageState();
}

class _GruImageState extends State<GruImage> {
  File? _imageFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(GruImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImage();
    }
  }

  String _getFilename() {
    if (widget.filename != null) return widget.filename!;
    try {
      final uri = Uri.parse(widget.url);
      return uri.pathSegments.last;
    } catch (_) {
      return 'image_${widget.url.hashCode}.jpg';
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _imageFile = null; // Clear previous image to avoid mismatch during transition
    });

    try {
      final file = await CacheService.instance.getFile('images', _getFilename(), widget.url);
      if (mounted) {
        setState(() {
          _imageFile = file;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_imageFile == null) {
      content = widget.placeholder ?? Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF1E1E1E),
        child: const Center(child: Icon(Icons.music_note, color: Colors.grey)),
      );
    } else {
      // Calculate cache sizes if not provided
      int? effectiveCacheWidth = widget.cacheWidth;
      int? effectiveCacheHeight = widget.cacheHeight;
      
      if (effectiveCacheWidth == null && effectiveCacheHeight == null && widget.width != null) {
        // If width/height is provided but no cache dimensions, use width * devicePixelRatio as a hint
        final dpr = MediaQuery.of(context).devicePixelRatio;
        effectiveCacheWidth = (widget.width! * dpr).round();
        if (widget.height != null) {
          effectiveCacheHeight = (widget.height! * dpr).round();
        }
      }

      content = Image.file(
        _imageFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: effectiveCacheWidth,
        cacheHeight: effectiveCacheHeight,
        errorBuilder: (context, error, stackTrace) {
          return widget.errorWidget ?? Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF1E1E1E),
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        },
      );
    }

    if (widget.borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: content,
      );
    }

    return content;
  }
}
import 'dart:io';
import 'package:flutter/material.dart';

class GruImage extends StatefulWidget {
  final String url;
  final String? filename;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? cacheWidth;
  final int? cacheHeight;

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

  @override
  State<GruImage> createState() => _GruImageState();
}

class _GruImageState extends State<GruImage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(GruImage oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return _buildError();
    }

    final bool isLocal = widget.url.startsWith('/') ||
        widget.url.startsWith('C:\\') ||
        widget.url.startsWith('file://') ||
        widget.url.startsWith('content://');

    Widget content;

    if (isLocal) {
      String path;
      try {
        final uri = Uri.parse(widget.url);
        if (uri.isScheme('file')) {
          path = uri.toFilePath();
        } else {
          path = widget.url;
        }
      } catch (_) {
        path = widget.url;
      }

      content = Image.file(
        File(path),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth ??
            (widget.width != null
                ? (widget.width! * MediaQuery.of(context).devicePixelRatio)
                    .round()
                : null),
        cacheHeight: widget.cacheHeight ??
            (widget.height != null
                ? (widget.height! * MediaQuery.of(context).devicePixelRatio)
                    .round()
                : null),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return widget.errorWidget ?? _buildError();
        },
      );
    } else {
      content = Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth ??
            (widget.width != null
                ? (widget.width! * MediaQuery.of(context).devicePixelRatio)
                    .round()
                : null),
        cacheHeight: widget.cacheHeight ??
            (widget.height != null
                ? (widget.height! * MediaQuery.of(context).devicePixelRatio)
                    .round()
                : null),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return widget.placeholder ?? _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          return widget.errorWidget ?? _buildError();
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

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.grey),
      ),
    );
  }
}

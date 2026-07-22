import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/cover_refresh_service.dart';

class AlbumArtImage extends StatefulWidget {
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
  final int? memCacheWidth;
  final int? memCacheHeight;
  final FilterQuality filterQuality;

  const AlbumArtImage({
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
    this.memCacheWidth,
    this.memCacheHeight,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<AlbumArtImage> createState() => _AlbumArtImageState();
}

class _AlbumArtImageState extends State<AlbumArtImage> {
  Future<String?>? _refreshFuture;
  String? _resolvedUrl;

  @override
  void didUpdateWidget(covariant AlbumArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.filename != widget.filename) {
      _refreshFuture = null;
      _resolvedUrl = null;
    }
  }

  bool get _canAttemptLazyRefresh =>
      widget.filename != null &&
      _looksLikeSongFile(widget.filename!) &&
      // A recycled tile would otherwise re-enqueue a song we already know has
      // no art, on every rebuild.
      !CoverRefreshService.instance.isKnownMiss(widget.filename!);

  void _scheduleLazyRefresh() {
    if (_refreshFuture != null || !_canAttemptLazyRefresh) return;

    _refreshFuture =
        CoverRefreshService.instance.ensureCoverForSong(widget.filename!).then(
      (path) {
        if (!mounted) return path;
        if (path != null && path.isNotEmpty) {
          setState(() {
            _resolvedUrl = path;
          });
        }
        return path;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      if (_canAttemptLazyRefresh) {
        _scheduleLazyRefresh();
        return widget.placeholder ?? _buildPlaceholder();
      }
      return _buildError();
    }

    final imageUrl = _resolvedUrl ?? widget.url;
    final bool isLocal = imageUrl.startsWith('/') ||
        imageUrl.startsWith('C:\\') ||
        imageUrl.startsWith('file://') ||
        imageUrl.startsWith('content://');

    int? effectiveMemCacheWidth = widget.memCacheWidth;
    int? effectiveMemCacheHeight = widget.memCacheHeight;

    if (effectiveMemCacheWidth == null && effectiveMemCacheHeight == null) {
      if (widget.width != null && widget.width! < 400) {
        effectiveMemCacheWidth = (widget.width! * 2.5).toInt();
      } else if (widget.height != null && widget.height! < 400) {
        effectiveMemCacheHeight = (widget.height! * 2.5).toInt();
      }
    }

    final filterQuality = widget.filterQuality;

    Widget content;

    if (isLocal) {
      String path;
      try {
        final uri = Uri.parse(imageUrl);
        if (uri.isScheme('file')) {
          path = uri.toFilePath();
        } else {
          path = imageUrl;
        }
      } catch (_) {
        path = imageUrl;
      }

      final file = File(path);
      if (!file.existsSync()) {
        _scheduleLazyRefresh();
        return widget.placeholder ?? _buildPlaceholder();
      }

      content = Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: filterQuality,
        cacheWidth: effectiveMemCacheWidth ?? widget.cacheWidth,
        cacheHeight: effectiveMemCacheHeight ?? widget.cacheHeight,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          _scheduleLazyRefresh();
          return widget.placeholder ?? _buildPlaceholder();
        },
      );
    } else {
      content = Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: filterQuality,
        cacheWidth: effectiveMemCacheWidth ?? widget.cacheWidth,
        cacheHeight: effectiveMemCacheHeight ?? widget.cacheHeight,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
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
    );
  }

  Widget _buildError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white24),
      ),
    );
  }

  bool _looksLikeSongFile(String value) {
    final lower = value.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic')) {
      return false;
    }

    return p.extension(lower).isNotEmpty;
  }
}

class StaticAlbumArtImage extends StatelessWidget {
  final String url;
  final String? filename;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const StaticAlbumArtImage({
    super.key,
    required this.url,
    this.filename,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _buildErrorWidget();
    }

    final bool isLocal = url.startsWith('/') ||
        url.startsWith('C:\\') ||
        url.startsWith('file://') ||
        url.startsWith('content://');

    Widget content;

    if (isLocal) {
      String path;
      try {
        final uri = Uri.parse(url);
        if (uri.isScheme('file')) {
          path = uri.toFilePath();
        } else {
          path = url;
        }
      } catch (_) {
        path = url;
      }

      content = Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        filterQuality: FilterQuality.low,
        cacheWidth: width != null ? (width! * 2).toInt() : null,
        cacheHeight: height != null ? (height! * 2).toInt() : null,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildErrorWidget();
        },
      );
    } else {
      content = Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        filterQuality: FilterQuality.low,
        cacheWidth: width != null ? (width! * 2).toInt() : null,
        cacheHeight: height != null ? (height! * 2).toInt() : null,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ?? _buildPlaceholderWidget();
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildErrorWidget();
        },
      );
    }

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholderWidget() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF1E1E1E),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white24),
      ),
    );
  }
}

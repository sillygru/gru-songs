import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'album_art_image.dart';
import '../../domain/models/cover_key.dart';
import '../../domain/services/media_decode.dart';
import '../../services/cache_service.dart';
import '../../services/cover_refresh_service.dart';
import '../../services/power_state_service.dart';

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

class _BlurredBackgroundState extends State<BlurredBackground> {
  File? _blurFile;

  /// Whether [_blurFile] is actually on disk.
  bool _blurFileExists = false;

  /// How long an uncached blur waits before the cover is decoded and blurred.
  ///
  /// Track changes and screen opens are already a burst of playback and palette
  /// work; generation is the heaviest single image op in the app, so it stands
  /// back a beat. The low-res art layer beneath stays visible meanwhile.
  static const Duration _generationDelay = Duration(milliseconds: 600);

  int _requestToken = 0;
  @override
  void initState() {
    super.initState();
    _loadBlurredImage();
  }

  @override
  void didUpdateWidget(BlurredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.filename != widget.filename) {
      _loadBlurredImage();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBlurredImage() async {
    _blurFile = null;
    _blurFileExists = false;

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
      _blurFileExists = true;
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() {});
    if (!mounted) return;

    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation != null && !animation.isCompleted) {
      final completer = Completer<void>();
      AnimationStatusListener? listener;
      listener = (status) {
        if (status == AnimationStatus.completed) {
          animation.removeStatusListener(listener!);
          if (!completer.isCompleted) completer.complete();
        }
      };
      animation.addStatusListener(listener);
      await completer.future;
      if (!mounted || token != _requestToken) return;
    }

    // Let the track-change burst (buffering, palette isolates, beat decode)
    // get a head start before this decode + blur eats the CPU.
    await Future<void>.delayed(_generationDelay);
    if (!mounted || token != _requestToken) return;

    var coverUrl = widget.url;
    final needsCoverRefresh = coverUrl.isEmpty ||
        (!coverUrl.startsWith('content://') &&
            !coverUrl.startsWith('http://') &&
            !coverUrl.startsWith('https://') &&
            !await File(CoverKey.normalizePath(coverUrl)).exists());
    if (needsCoverRefresh && filename.isNotEmpty) {
      coverUrl =
          await CoverRefreshService.instance.ensureCoverForSong(filename) ??
              coverUrl;
    }
    if (coverUrl.isEmpty) return;

    final success = await MediaDecode().generateBlurredImage(
      inputPath: coverUrl,
      outputPath: blurFile.path,
    );

    if (!mounted || token != _requestToken) return;

    if (success && await blurFile.exists()) {
      setState(() {
        _blurFile = blurFile;
        _blurFileExists = true;
      });
    }
  }

  bool get _hasBlurredBackground => _blurFile != null && _blurFileExists;

  Widget _buildImageLayers({double? squareSize}) {
    // Cache the decoded blur at roughly the size it is drawn: avoids decoding a
    // 1080p-3000px file for a box that is a few hundred points wide, and keeps
    // the image cache from evicting list thumbnails.
    final int? cacheDim = squareSize == null
        ? null
        : (squareSize * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(512, 1024);
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
                cacheWidth: cacheDim,
                cacheHeight: cacheDim,
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
          // Blur layers displayed in a square OverflowBox so no rectangular
          // borders show during rotation. The rotating subtree is isolated in
          // its own RepaintBoundary so the compositor can cache it as a
          // texture layer: rotation then becomes a GPU transform, not a
          // full raster, and the static gradient/glass above do not repaint.
          LayoutBuilder(
            builder: (context, constraints) {
              // Diagonal of the viewport covers 45deg rotation; 1.02 accounts
              // for the 1.5% breathing scale so corners never clip.
              final viewportMax =
                  math.max(constraints.maxWidth, constraints.maxHeight);
              final squareSize = viewportMax * math.sqrt2 * 1.02;
              return OverflowBox(
                maxWidth: squareSize,
                maxHeight: squareSize,
                alignment: Alignment.center,
                child: ClipRect(
                  child: RepaintBoundary(
                    child: _ThrottledSpin(
                      key: ValueKey(widget.filename),
                      enabled: widget.slowSpin,
                      child: _buildImageLayers(squareSize: squareSize),
                    ),
                  ),
                ),
              );
            },
          ),

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

/// Rotates the cached backdrop at 15Hz. Isolated in its own RepaintBoundary the
/// rotation is a compositor transform (not a 1.3MP raster), so 15Hz is
/// indistinguishable from 60Hz at 90s per rotation (0.4deg/frame vs 0.1deg) but
/// cuts compositor wake-ups by 4x; background stops entirely when backgrounded
/// or paused, and shards via cacheWidth keep decode cheap.
class _ThrottledSpin extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const _ThrottledSpin({
    super.key,
    required this.enabled,
    required this.child,
  });

  @override
  State<_ThrottledSpin> createState() => _ThrottledSpinState();
}

class _ThrottledSpinState extends State<_ThrottledSpin>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _paintInterval = Duration(microseconds: 66667);
  static const Duration _powerSaveInterval = Duration(microseconds: 100000);
  static const Duration _spinDuration = Duration(seconds: 90);

  late final Ticker _ticker;
  Duration? _lastPaint;
  Duration _lastElapsed = Duration.zero;
  Duration _elapsedBase = Duration.zero;
  double _value = 0;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _ticker = createTicker(_onTick);
    PowerStateService.instance.powerSave.addListener(_onPowerSaveChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ThrottledSpin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    _syncTicker();
    if (!widget.enabled && mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.enabled && _appActive) {
      _lastPaint = null;
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _elapsedBase += _lastElapsed;
      _lastElapsed = Duration.zero;
      _ticker.stop();
    }
  }

  void _onPowerSaveChanged() {
    // No restart needed — interval is checked on next tick.
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final last = _lastPaint;
    final interval = PowerStateService.instance.powerSave.value
        ? _powerSaveInterval
        : _paintInterval;
    if (last != null && elapsed - last < interval) return;
    _lastPaint = elapsed;
    _lastElapsed = elapsed;
    final totalElapsed = _elapsedBase + elapsed;
    _value = totalElapsed.inMicroseconds / _spinDuration.inMicroseconds;
    if (_value >= 1) _value %= 1;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PowerStateService.instance.powerSave.removeListener(_onPowerSaveChanged);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final angle = _value * 2 * math.pi;
    final scale = 1.0 + 0.015 * math.sin(angle);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

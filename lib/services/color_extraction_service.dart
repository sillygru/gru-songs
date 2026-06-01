import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

class ExtractedPalette {
  final Color? used;
  final Color mixedColor;
  final List<Color> palette;

  Color get color => used ?? mixedColor;

  const ExtractedPalette({
    this.used,
    required this.mixedColor,
    required this.palette,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExtractedPalette) return false;
    if (used != other.used) return false;
    if (mixedColor != other.mixedColor) return false;
    if (palette.length != other.palette.length) return false;
    for (int i = 0; i < palette.length; i++) {
      if (palette[i] != other.palette[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = Object.hash(used, mixedColor, palette.length);
    for (final color in palette) {
      hash = Object.hash(hash, color);
    }
    return hash;
  }

  ExtractedPalette.single(Color color)
      : used = null,
        mixedColor = color,
        palette = [color];

  factory ExtractedPalette.create({
    Color? used,
    required List<Color> palette,
  }) {
    final mixed = ExtractedPalette.mixColors(palette.take(10).toList());
    return ExtractedPalette(
      used: used,
      mixedColor: mixed,
      palette: palette,
    );
  }

  static Color mixColors(List<Color> colors) {
    if (colors.isEmpty) return Colors.transparent;
    int red = 0;
    int green = 0;
    int blue = 0;

    for (final color in colors) {
      final intValue = color.toARGB32();
      red += (intValue >> 16) & 0xFF;
      green += (intValue >> 8) & 0xFF;
      blue += intValue & 0xFF;
    }

    red ~/= colors.length;
    green ~/= colors.length;
    blue ~/= colors.length;

    return Color.fromARGB(255, red, green, blue);
  }

  factory ExtractedPalette.fromJson(Map<String, dynamic> json) {
    final paletteList =
        (json['palette'] as List?)?.map((e) => Color(e as int)).toList() ?? [];
    final mixedColor = json['mixedColor'] is int
        ? Color(json['mixedColor'] as int)
        : ExtractedPalette.mixColors(paletteList.take(10).toList());
    return ExtractedPalette(
      used: json['used'] != null ? Color(json['used'] as int) : null,
      mixedColor: mixedColor,
      palette: paletteList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'used': used?.toARGB32(),
      'mixedColor': mixedColor.toARGB32(),
      'palette': palette.map((e) => e.toARGB32()).toList(),
    };
  }

  ExtractedPalette withDelightned() {
    if (palette.isEmpty) return this;
    final delightnedColors = palette.map((c) => _delightnedColor(c)).toList();
    final delightnedMix =
        ExtractedPalette.mixColors(delightnedColors.take(10).toList());
    return ExtractedPalette(
      used: used != null ? _delightnedColor(used!) : null,
      mixedColor: delightnedMix,
      palette: delightnedColors,
    );
  }

  ExtractedPalette withAlpha(int alpha) {
    return ExtractedPalette(
      used: used?.withAlpha(alpha),
      mixedColor: mixedColor.withAlpha(alpha),
      palette: palette,
    );
  }

  ExtractedPalette withDelightnedAndAlpha(int alpha) {
    final delightned = withDelightned();
    return delightned.withAlpha(alpha);
  }

  static Color _delightnedColor(Color color) {
    final luminance = color.computeLuminance();
    if (luminance <= 0.1 || luminance >= 0.9) return color;
    final hslColor = HSLColor.fromColor(color);
    return hslColor.withLightness(0.4).toColor();
  }

  static Color _lighterColor(Color color) {
    final luminance = color.computeLuminance();
    if (luminance <= 0.1 || luminance >= 0.9) return color;
    final hslColor = HSLColor.fromColor(color);
    return hslColor.withLightness(0.64).toColor();
  }

  ExtractedPalette withLighter() {
    if (palette.isEmpty) return this;
    final lighterColors = palette.map((c) => _lighterColor(c)).toList();
    final lighterMix =
        ExtractedPalette.mixColors(lighterColors.take(10).toList());
    return ExtractedPalette(
      used: used != null ? _lighterColor(used!) : null,
      mixedColor: lighterMix,
      palette: lighterColors,
    );
  }
}

class ColorExtractionService {
  // Insertion-ordered map: most recently accessed keys sit at the end. On
  // each cache hit we re-insert to mark it as fresh, so the head of the
  // map is always the least-recently-used entry we can evict when the cap
  // is hit.
  static LinkedHashMap<String, ExtractedPalette> _paletteCache =
      LinkedHashMap();
  static final Map<String, Future<ExtractedPalette?>> _pendingPalettes = {};
  static File? _cacheFile;
  static Directory? _paletteDir;
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static Timer? _saveDebounceTimer;
  static const Duration _saveDebounce = Duration(seconds: 5);
  static const int _maxCachedPalettes = 500;

  static Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = _initInternal();
    await _initFuture;
  }

  static Future<void> _initInternal() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      _cacheFile = File(p.join(appSupportDir.path, 'palette_cache.json'));
      _paletteDir = Directory(p.join(appSupportDir.path, 'palettes'));

      if (!await _paletteDir!.exists()) {
        await _paletteDir!.create(recursive: true);
      }

      if (await _cacheFile!.exists()) {
        final Map<String, dynamic> json =
            await compute(_loadPaletteCacheSnapshot, _cacheFile!.path);
        final loaded = <String, ExtractedPalette>{};
        json.forEach((key, value) {
          loaded[key] =
              ExtractedPalette.fromJson(value as Map<String, dynamic>);
        });
        _paletteCache = LinkedHashMap.from(loaded);
        debugPrint(
            'ColorExtractionService: Loaded ${_paletteCache.length} cached palettes');
      }
    } catch (e) {
      debugPrint('ColorExtractionService init error: $e');
    } finally {
      _initialized = true;
      _initFuture = null;
    }
  }

  static Future<ExtractedPalette?> extractPalette(
    String? imagePath, {
    bool useIsolate = false,
  }) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    await init();

    final cached = _paletteCache[imagePath];
    if (cached != null) {
      // Re-insert to mark as recently used for the LRU eviction policy.
      _paletteCache.remove(imagePath);
      _paletteCache[imagePath] = cached;
      return cached;
    }

    final pending = _pendingPalettes[imagePath];
    if (pending != null) {
      return pending;
    }

    final extraction = _extractAndCachePalette(
      imagePath,
      useIsolate: useIsolate,
    );
    _pendingPalettes[imagePath] = extraction;
    try {
      return await extraction;
    } catch (e) {
      debugPrint('Error extracting palette from $imagePath: $e');
      return null;
    } finally {
      if (identical(_pendingPalettes[imagePath], extraction)) {
        _pendingPalettes.remove(imagePath);
      }
    }
  }

  static Future<ExtractedPalette?> _extractAndCachePalette(
    String imagePath, {
    required bool useIsolate,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final palette = await _extractPalette(file, useIsolate: useIsolate);
    if (palette == null) return null;

    final extractedPalette = ExtractedPalette.create(
      palette: palette,
    );

    _paletteCache[imagePath] = extractedPalette;
    // Cap the in-memory cache to avoid unbounded growth in long sessions.
    // Persisted cache on disk keeps the full set so future restarts reload
    // what was previously extracted.
    _enforceMaxSize();
    _scheduleCacheSave();
    return extractedPalette;
  }

  static void _enforceMaxSize() {
    while (_paletteCache.length > _maxCachedPalettes) {
      final oldestKey = _paletteCache.keys.first;
      _paletteCache.remove(oldestKey);
    }
  }

  static Future<List<Color>?> _extractPalette(
    File imageFile, {
    bool useIsolate = false,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (useIsolate) {
        return await compute(_extractKMeansPalette, bytes);
      } else {
        return _extractKMeansPalette(bytes);
      }
    } catch (_) {
      return null;
    }
  }

  static List<Color> _extractKMeansPalette(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return [];

    image = img.copyResize(image, height: 100);
    image = img.gaussianBlur(image, radius: 2);

    final pixels = _imageToPixelList(image);
    if (pixels.isEmpty) return [];

    final clusters = _kMeansClustering(pixels, k: 5, maxIterations: 20);

    clusters.sort((a, b) => b.population.compareTo(a.population));

    return clusters
        .map((c) =>
            Color.fromARGB(255, c.centroid.r, c.centroid.g, c.centroid.b))
        .toList();
  }

  static List<_Pixel> _imageToPixelList(img.Image image) {
    final pixels = <_Pixel>[];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels.add(_Pixel(
          r: pixel.r.toInt(),
          g: pixel.g.toInt(),
          b: pixel.b.toInt(),
        ));
      }
    }
    return pixels;
  }

  static List<_Cluster> _kMeansClustering(
    List<_Pixel> pixels, {
    required int k,
    required int maxIterations,
  }) {
    if (pixels.isEmpty || k <= 0) return [];
    if (k > pixels.length) k = pixels.length;

    final random = Random();
    final clusters = <_Cluster>[];

    for (var i = 0; i < k; i++) {
      final pixel = pixels[random.nextInt(pixels.length)];
      clusters.add(_Cluster(centroid: pixel));
    }

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      for (final cluster in clusters) {
        cluster.pixels.clear();
      }

      for (final pixel in pixels) {
        _Cluster? nearest;
        var minDistance = double.infinity;

        for (final cluster in clusters) {
          final distance = _colorDistance(pixel, cluster.centroid);
          if (distance < minDistance) {
            minDistance = distance;
            nearest = cluster;
          }
        }

        nearest?.pixels.add(pixel);
      }

      var moved = false;
      for (final cluster in clusters) {
        if (cluster.pixels.isNotEmpty) {
          final newCentroid = _calculateCentroid(cluster.pixels);
          if (_colorDistance(cluster.centroid, newCentroid) > 1) {
            cluster.centroid = newCentroid;
            moved = true;
          }
        }
      }

      if (!moved) break;
    }

    return clusters.where((c) => c.pixels.isNotEmpty).toList();
  }

  static double _colorDistance(_Pixel a, _Pixel b) {
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    return sqrt(dr * dr + dg * dg + db * db);
  }

  static _Pixel _calculateCentroid(List<_Pixel> pixels) {
    var r = 0, g = 0, b = 0;
    for (final p in pixels) {
      r += p.r;
      g += p.g;
      b += p.b;
    }
    return _Pixel(
      r: r ~/ pixels.length,
      g: g ~/ pixels.length,
      b: b ~/ pixels.length,
    );
  }

  static Future<Color?> extractColor(
    String? imagePath, {
    bool useIsolate = false,
  }) async {
    final palette = await extractPalette(imagePath, useIsolate: useIsolate);
    return palette?.color;
  }

  static Future<bool> hasCachedPalette(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return false;
    await init();
    return _paletteCache.containsKey(imagePath);
  }

  static Future<void> pruneCacheToImagePaths(Set<String> imagePaths) async {
    await init();
    final keepPaths = imagePaths.where((path) => path.isNotEmpty).toSet();
    final originalLength = _paletteCache.length;
    _paletteCache.removeWhere((path, _) => !keepPaths.contains(path));
    if (_paletteCache.length != originalLength) {
      _scheduleCacheSave();
    }
  }

  static void _scheduleCacheSave() {
    // Coalesce multiple back-to-back extractions (common during a fresh
    // library scan) into a single disk write. 5 s is a comfortable window
    // for bursts without risking data loss if the process is killed.
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(_saveDebounce, () {
      _saveDebounceTimer = null;
      _saveCacheToDisk();
    });
  }

  static Future<void> _saveCacheToDisk() async {
    if (_cacheFile == null) return;
    try {
      final snapshot = _paletteCache;
      final json = snapshot.map((key, value) => MapEntry(key, value.toJson()));
      await _cacheFile!.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Error saving palette cache: $e');
    }
  }

  static Future<void> clearCache() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _paletteCache.clear();
    _pendingPalettes.clear();
    if (_cacheFile != null && await _cacheFile!.exists()) {
      await _cacheFile!.delete();
    }
    if (_paletteDir != null && await _paletteDir!.exists()) {
      await _paletteDir!.delete(recursive: true);
      await _paletteDir!.create();
    }
  }

  static Future<int> getCacheSize() async {
    if (_cacheFile == null || !await _cacheFile!.exists()) return 0;
    return await _cacheFile!.length();
  }

  static int _batchProgress = 0;
  static int _batchTotal = 0;
  static bool _batchCancelled = false;

  static double? get batchProgress =>
      _batchTotal > 0 ? _batchProgress / _batchTotal : null;

  static Future<void> extractAllPalettes(
    List<String> imagePaths, {
    bool useIsolate = true,
    void Function(int progress, int total)? onProgress,
  }) async {
    await init();
    _batchProgress = 0;
    _batchTotal = imagePaths.length;
    _batchCancelled = false;

    for (int i = 0; i < imagePaths.length; i++) {
      if (_batchCancelled) break;

      final path = imagePaths[i];
      if (!_paletteCache.containsKey(path)) {
        await extractPalette(path, useIsolate: useIsolate);
      }

      _batchProgress = i + 1;
      onProgress?.call(_batchProgress, _batchTotal);
    }

    _batchProgress = 0;
    _batchTotal = 0;
  }

  static void cancelBatchExtraction() {
    _batchCancelled = true;
  }
}

Future<Map<String, dynamic>> _loadPaletteCacheSnapshot(String cachePath) async {
  final cacheFile = File(cachePath);
  if (!await cacheFile.exists()) return {};

  final jsonString = await cacheFile.readAsString();
  final decoded = jsonDecode(jsonString);
  if (decoded is Map<String, dynamic>) return decoded;
  return {};
}

class _Pixel {
  final int r;
  final int g;
  final int b;

  _Pixel({required this.r, required this.g, required this.b});
}

class _Cluster {
  _Pixel centroid;
  final List<_Pixel> pixels = [];

  _Cluster({required this.centroid});

  int get population => pixels.length;
}

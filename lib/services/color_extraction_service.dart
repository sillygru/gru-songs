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

import '../domain/services/cover_palette.dart';

class ExtractedPalette {
  final Color? used;

  /// The cover's accent, already corrected for legibility by
  /// [selectAccent]. Consumers use it as-is — no second lightening,
  /// saturating or blending pass.
  final Color accent;

  /// The cover has no usable chroma, so the theme falls back to its OLED
  /// variant instead of showing an invented hue.
  final bool isNeutral;

  /// Flat average of the swatches. Only meaningful for backdrops and scrims,
  /// where a muddy blend of everything is exactly what is wanted — never as an
  /// accent.
  final Color mixedColor;

  final List<Color> palette;

  Color get color => used ?? accent;

  const ExtractedPalette({
    this.used,
    required this.accent,
    required this.isNeutral,
    required this.mixedColor,
    required this.palette,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExtractedPalette) return false;
    if (used != other.used) return false;
    if (accent != other.accent) return false;
    if (isNeutral != other.isNeutral) return false;
    if (mixedColor != other.mixedColor) return false;
    if (palette.length != other.palette.length) return false;
    for (int i = 0; i < palette.length; i++) {
      if (palette[i] != other.palette[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = Object.hash(used, accent, isNeutral, mixedColor, palette.length);
    for (final color in palette) {
      hash = Object.hash(hash, color);
    }
    return hash;
  }

  ExtractedPalette.single(Color color)
      : used = null,
        accent = color,
        isNeutral = false,
        mixedColor = color,
        palette = [color];

  factory ExtractedPalette.create({
    Color? used,
    required List<Swatch> swatches,
  }) {
    final selected = selectAccent(swatches);
    final mixed =
        ExtractedPalette.mixColors(selected.swatches.take(10).toList());
    return ExtractedPalette(
      used: used,
      accent: selected.accent,
      isNeutral: selected.isNeutral,
      mixedColor: mixed,
      palette: selected.swatches,
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
      accent: json['accent'] is int
          ? Color(json['accent'] as int)
          : normalizeAccent(mixedColor),
      isNeutral: json['isNeutral'] as bool? ?? false,
      mixedColor: mixedColor,
      palette: paletteList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'used': used?.toARGB32(),
      'accent': accent.toARGB32(),
      'isNeutral': isNeutral,
      'mixedColor': mixedColor.toARGB32(),
      'palette': palette.map((e) => e.toARGB32()).toList(),
    };
  }
}

/// A cached palette plus the identity of the cover file it came from, so an
/// entry can be invalidated when the artwork behind the path is rewritten
/// (cover refresh, metadata edits, standardisation).
class _CacheEntry {
  final ExtractedPalette palette;
  final int size;
  final int mtimeMs;

  const _CacheEntry({
    required this.palette,
    required this.size,
    required this.mtimeMs,
  });

  bool matches(FileStat stat) =>
      stat.size == size && stat.modified.millisecondsSinceEpoch == mtimeMs;

  Map<String, dynamic> toJson() => {
        'palette': palette.toJson(),
        'size': size,
        'mtimeMs': mtimeMs,
      };

  static _CacheEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final palette = json['palette'];
    if (palette is! Map<String, dynamic>) return null;
    return _CacheEntry(
      palette: ExtractedPalette.fromJson(palette),
      size: json['size'] as int? ?? -1,
      mtimeMs: json['mtimeMs'] as int? ?? -1,
    );
  }
}

class ColorExtractionService {
  /// Bumped whenever the extraction algorithm changes. The persisted cache is
  /// discarded wholesale on a mismatch — without this, every already-scanned
  /// library keeps serving colours computed by the old algorithm forever, and
  /// no fix here would ever reach an existing install.
  static const int _cacheVersion = 2;

  // Insertion-ordered map: most recently accessed keys sit at the end. On
  // each cache hit we re-insert to mark it as fresh, so the head of the
  // map is always the least-recently-used entry we can evict when the cap
  // is hit.
  static LinkedHashMap<String, _CacheEntry> _paletteCache = LinkedHashMap();
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
        if (json['version'] != _cacheVersion) {
          debugPrint('ColorExtractionService: Discarding stale palette cache '
              '(v${json['version']} != v$_cacheVersion)');
          await _cacheFile!.delete();
        } else {
          final entries = json['entries'];
          final loaded = <String, _CacheEntry>{};
          if (entries is Map<String, dynamic>) {
            entries.forEach((key, value) {
              final entry = _CacheEntry.fromJson(value);
              if (entry != null) loaded[key] = entry;
            });
          }
          _paletteCache = LinkedHashMap.from(loaded);
          debugPrint(
              'ColorExtractionService: Loaded ${_paletteCache.length} cached palettes');
        }
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
      if (await _isEntryFresh(imagePath, cached)) {
        // Re-insert to mark as recently used for the LRU eviction policy.
        _paletteCache.remove(imagePath);
        _paletteCache[imagePath] = cached;
        return cached.palette;
      }
      _paletteCache.remove(imagePath);
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

  /// An entry survives only while the file behind the path is byte-identical to
  /// the one it was computed from. Covers are rewritten in place by metadata
  /// edits and cover refresh, and a path-only key would keep serving the old
  /// artwork's colour.
  static Future<bool> _isEntryFresh(String imagePath, _CacheEntry entry) async {
    if (entry.size < 0) return true;
    try {
      final stat = await File(imagePath).stat();
      if (stat.type == FileSystemEntityType.notFound) return true;
      return entry.matches(stat);
    } catch (_) {
      return true;
    }
  }

  static Future<ExtractedPalette?> _extractAndCachePalette(
    String imagePath, {
    required bool useIsolate,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final swatches = await _extractSwatches(file, useIsolate: useIsolate);
    if (swatches == null || swatches.isEmpty) return null;

    final extractedPalette = ExtractedPalette.create(swatches: swatches);

    final stat = await file.stat();
    _paletteCache[imagePath] = _CacheEntry(
      palette: extractedPalette,
      size: stat.size,
      mtimeMs: stat.modified.millisecondsSinceEpoch,
    );
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

  static Future<List<Swatch>?> _extractSwatches(
    File imageFile, {
    bool useIsolate = false,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (useIsolate) {
        return await compute(_extractKMeansSwatches, bytes);
      } else {
        return _extractKMeansSwatches(bytes);
      }
    } catch (_) {
      return null;
    }
  }

  static List<Swatch> _extractKMeansSwatches(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return [];

    image = img.copyResize(image, height: 100);
    image = img.gaussianBlur(image, radius: 2);

    final pixels = _imageToPixelList(image);
    if (pixels.isEmpty) return [];

    final clusters = _kMeansClustering(pixels, k: 5, maxIterations: 20);

    clusters.sort((a, b) => b.population.compareTo(a.population));

    return clusters
        .map((c) => Swatch(
              color:
                  Color.fromARGB(255, c.centroid.r, c.centroid.g, c.centroid.b),
              population: c.population,
            ))
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

  /// Seeds the clustering from the pixels themselves, so the same cover always
  /// produces the same palette — across runs, and between the main-thread and
  /// `compute()` paths. An unseeded `Random()` let one cover resolve to
  /// different accents on different launches, and whichever result happened to
  /// land in the cache was then frozen there.
  static int _pixelSeed(List<_Pixel> pixels) {
    var hash = pixels.length;
    // Sampling ~256 pixels is plenty to fingerprint the image and keeps this
    // off the hot path for large covers.
    final step = max(1, pixels.length ~/ 256);
    for (var i = 0; i < pixels.length; i += step) {
      final p = pixels[i];
      hash = 0x1fffffff & (hash * 31 + ((p.r << 16) | (p.g << 8) | p.b));
    }
    return hash;
  }

  static List<_Cluster> _kMeansClustering(
    List<_Pixel> pixels, {
    required int k,
    required int maxIterations,
  }) {
    if (pixels.isEmpty || k <= 0) return [];
    if (k > pixels.length) k = pixels.length;

    final random = Random(_pixelSeed(pixels));
    final clusters = <_Cluster>[];

    // k-means++ seeding: the first centroid is random, each subsequent one is
    // drawn with probability proportional to its squared distance from the
    // nearest centroid already chosen. Spreading the seeds out this way stops
    // several of them landing inside one large flat region — the failure mode
    // that leaves a cover's only saturated area unrepresented.
    clusters.add(_Cluster(centroid: pixels[random.nextInt(pixels.length)]));

    final nearest = List<double>.filled(pixels.length, double.infinity);
    while (clusters.length < k) {
      var total = 0.0;
      final last = clusters.last.centroid;
      for (var i = 0; i < pixels.length; i++) {
        final d = _colorDistance(pixels[i], last);
        final dSquared = d * d;
        if (dSquared < nearest[i]) nearest[i] = dSquared;
        total += nearest[i];
      }

      if (total <= 0) break;

      var target = random.nextDouble() * total;
      var chosen = pixels.length - 1;
      for (var i = 0; i < pixels.length; i++) {
        target -= nearest[i];
        if (target <= 0) {
          chosen = i;
          break;
        }
      }
      clusters.add(_Cluster(centroid: pixels[chosen]));
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
      final entries =
          snapshot.map((key, value) => MapEntry(key, value.toJson()));
      await _cacheFile!.writeAsString(jsonEncode({
        'version': _cacheVersion,
        'entries': entries,
      }));
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

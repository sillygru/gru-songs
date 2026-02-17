import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:palette_generator/palette_generator.dart';

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
  static Map<String, ExtractedPalette> _paletteCache = {};
  static File? _cacheFile;
  static Directory? _paletteDir;
  static bool _initialized = false;

  static const int _resizeHeight = 240;
  static const int _maximumColorCount = 28;
  static const Duration _timeout = Duration(seconds: 5);

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      _cacheFile = File(p.join(appSupportDir.path, 'palette_cache.json'));
      _paletteDir = Directory(p.join(appSupportDir.path, 'palettes'));

      if (!await _paletteDir!.exists()) {
        await _paletteDir!.create(recursive: true);
      }

      if (await _cacheFile!.exists()) {
        final jsonString = await _cacheFile!.readAsString();
        final Map<String, dynamic> json = jsonDecode(jsonString);
        _paletteCache = json.map((key, value) => MapEntry(
            key, ExtractedPalette.fromJson(value as Map<String, dynamic>)));
        debugPrint(
            'ColorExtractionService: Loaded ${_paletteCache.length} cached palettes');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('ColorExtractionService init error: $e');
      _initialized = true;
    }
  }

  static Future<ExtractedPalette?> extractPalette(
    String? imagePath, {
    bool useIsolate = false,
  }) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    await init();

    if (_paletteCache.containsKey(imagePath)) {
      return _paletteCache[imagePath];
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final palette = await _extractPalette(file, useIsolate: useIsolate);
      if (palette == null) return null;

      final extractedPalette = ExtractedPalette.create(
        palette: palette,
      );

      _paletteCache[imagePath] = extractedPalette;
      await _saveCacheToDisk();
      return extractedPalette;
    } catch (e) {
      debugPrint('Error extracting palette from $imagePath: $e');
      return null;
    }
  }

  static Future<List<Color>?> _extractPalette(
    File imageFile, {
    bool useIsolate = false,
  }) async {
    final imageProvider = ResizeImage(
      FileImage(imageFile),
      height: _resizeHeight,
    );

    try {
      if (useIsolate) {
        return await _extractPaletteInIsolate(imageProvider);
      } else {
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          filters: const [],
          maximumColorCount: _maximumColorCount,
          timeout: _timeout,
        );
        return palette.colors.toList();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<List<Color>?> _extractPaletteInIsolate(
      ImageProvider imageProvider) async {
    final ImageStream stream = imageProvider.resolve(
      const ImageConfiguration(size: null, devicePixelRatio: 1.0),
    );
    final Completer<ui.Image> imageCompleter = Completer<ui.Image>();
    Timer? loadFailureTimeout;
    late ImageStreamListener listener;
    listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
      loadFailureTimeout?.cancel();
      stream.removeListener(listener);
      imageCompleter.complete(info.image);
    });

    loadFailureTimeout = Timer(_timeout, () {
      stream.removeListener(listener);
      imageCompleter.completeError(
        TimeoutException('Timeout occurred trying to load image'),
      );
    });

    stream.addListener(listener);

    try {
      final ui.Image image = await imageCompleter.future;
      final ByteData? imageData = await image.toByteData();
      if (imageData == null) return null;

      final encImg = EncodedImage(
        imageData,
        width: image.width,
        height: image.height,
      );

      final colors = await compute(_extractPaletteCompute, encImg);
      return colors;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Color>> _extractPaletteCompute(EncodedImage encImg) async {
    final result = await PaletteGenerator.fromByteData(
      encImg,
      filters: const [],
      maximumColorCount: _maximumColorCount,
    );
    return result.colors.toList();
  }

  static Future<Color?> extractColor(
    String? imagePath, {
    bool useIsolate = false,
  }) async {
    final palette = await extractPalette(imagePath, useIsolate: useIsolate);
    return palette?.color;
  }

  static Future<void> _saveCacheToDisk() async {
    if (_cacheFile == null) return;
    try {
      final json =
          _paletteCache.map((key, value) => MapEntry(key, value.toJson()));
      await _cacheFile!.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Error saving palette cache: $e');
    }
  }

  static Future<void> clearCache() async {
    _paletteCache.clear();
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

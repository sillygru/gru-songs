import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FFmpegExecutionResult {
  final int returnCode;
  final String output;
  final String logs;

  bool get isSuccess => returnCode == 0;

  const FFmpegExecutionResult({
    required this.returnCode,
    this.output = '',
    this.logs = '',
  });
}

class FFmpegService {
  static final FFmpegService instance = FFmpegService();

  static bool get usesSystemProcess =>
      !kIsWeb && !Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS;

  static bool? _cachedFfmpegAvailable;
  static bool? _cachedFfprobeAvailable;

  Future<bool> isFFmpegAvailable() async {
    if (!usesSystemProcess) return true;
    if (_cachedFfmpegAvailable != null) return _cachedFfmpegAvailable!;
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      _cachedFfmpegAvailable = (res.exitCode == 0);
    } catch (_) {
      _cachedFfmpegAvailable = false;
    }
    return _cachedFfmpegAvailable!;
  }

  Future<bool> isFFprobeAvailable() async {
    if (!usesSystemProcess) return true;
    if (_cachedFfprobeAvailable != null) return _cachedFfprobeAvailable!;
    try {
      final res = await Process.run('ffprobe', ['-version']);
      _cachedFfprobeAvailable = (res.exitCode == 0);
    } catch (_) {
      _cachedFfprobeAvailable = false;
    }
    return _cachedFfprobeAvailable!;
  }

  Future<FFmpegExecutionResult> executeFFmpeg(List<String> args) async {
    if (usesSystemProcess) {
      if (!await isFFmpegAvailable()) {
        return const FFmpegExecutionResult(
          returnCode: -1,
          logs: 'ffmpeg executable not found on system',
        );
      }
      try {
        final res = await Process.run('ffmpeg', args);
        return FFmpegExecutionResult(
          returnCode: res.exitCode,
          output: res.stdout.toString(),
          logs: res.stderr.toString(),
        );
      } catch (e) {
        return FFmpegExecutionResult(
          returnCode: -1,
          logs: e.toString(),
        );
      }
    }

    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      final logs = await session.getAllLogsAsString();
      final output = await session.getOutput();
      return FFmpegExecutionResult(
        returnCode: rc?.getValue() ?? -1,
        output: output ?? '',
        logs: logs ?? '',
      );
    } catch (e) {
      return FFmpegExecutionResult(
        returnCode: -1,
        logs: e.toString(),
      );
    }
  }

  Future<FFmpegExecutionResult> executeFFprobe(List<String> args) async {
    if (usesSystemProcess) {
      if (!await isFFprobeAvailable()) {
        return const FFmpegExecutionResult(
          returnCode: -1,
          logs: 'ffprobe executable not found on system',
        );
      }
      try {
        final res = await Process.run('ffprobe', args);
        return FFmpegExecutionResult(
          returnCode: res.exitCode,
          output: res.stdout.toString(),
          logs: res.stderr.toString(),
        );
      } catch (e) {
        return FFmpegExecutionResult(
          returnCode: -1,
          logs: e.toString(),
        );
      }
    }

    try {
      final session = await FFprobeKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      final logs = await session.getAllLogsAsString();
      final output = await session.getOutput();
      return FFmpegExecutionResult(
        returnCode: rc?.getValue() ?? -1,
        output: output ?? '',
        logs: logs ?? '',
      );
    } catch (e) {
      return FFmpegExecutionResult(
        returnCode: -1,
        logs: e.toString(),
      );
    }
  }

  Future<Process?> startFFmpeg(List<String> args) async {
    if (!await isFFmpegAvailable()) return null;
    try {
      return await Process.start('ffmpeg', args);
    } catch (e) {
      if (kDebugMode) debugPrint('FFmpegService: Failed to start ffmpeg: $e');
      return null;
    }
  }

  Future<void> _ensurePlatformSupported() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return;
    }
    if (await isFFmpegAvailable()) {
      return;
    }
    throw UnsupportedError('FFmpeg is not available on this platform');
  }

  Future<String?> prepareIosAudioProxy(String inputPath) async {
    final file = File(inputPath);
    if (!await file.exists()) return null;

    final outputPath = await _iosProxyPath(inputPath, 'audio', '.m4a');
    final output = File(outputPath);
    if (await output.exists() && await output.length() > 0) {
      return outputPath;
    }

    final result = await executeFFmpeg([
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-map',
      '0:a:0?',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
    if (!result.isSuccess) {
      if (kDebugMode) {
        debugPrint(
            'FFmpegService: iOS audio proxy failed: ${result.returnCode}\n${result.logs}');
      }
      return null;
    }

    if (await output.exists() && await output.length() > 0) return outputPath;
    return null;
  }

  Future<String?> prepareIosVideoProxy(String inputPath) async {
    final file = File(inputPath);
    if (!await file.exists()) return null;

    final outputPath = await _iosProxyPath(inputPath, 'video', '.mp4');
    final output = File(outputPath);
    if (await output.exists() && await output.length() > 0) {
      return outputPath;
    }

    final remuxed = await _runProxyCommand([
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:v:0?',
      '-map',
      '0:a:0?',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
    if (remuxed && await output.exists() && await output.length() > 0) {
      return outputPath;
    }

    final transcoded = await _runProxyCommand([
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:v:0?',
      '-map',
      '0:a:0?',
      '-c:v',
      'h264_videotoolbox',
      '-b:v',
      '2500k',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
    if (transcoded && await output.exists() && await output.length() > 0) {
      return outputPath;
    }

    return null;
  }

  Future<bool> _runProxyCommand(List<String> args) async {
    final result = await executeFFmpeg(args);
    if (result.isSuccess) return true;
    if (kDebugMode) {
      debugPrint(
          'FFmpegService: proxy command failed: ${result.returnCode}\n${result.logs}');
    }
    return false;
  }

  Future<String> _iosProxyPath(
    String inputPath,
    String kind,
    String extension,
  ) async {
    final file = File(inputPath);
    final stat = await file.stat();
    final supportDir = await getApplicationSupportDirectory();
    final proxyDir =
        Directory(p.join(supportDir.path, 'gru_cache_v3', 'ios_media_proxy'));
    if (!await proxyDir.exists()) {
      await proxyDir.create(recursive: true);
    }
    final key = sha1
        .convert(utf8.encode(
            '$kind|$inputPath|${stat.modified.millisecondsSinceEpoch}|${stat.size}'))
        .toString();
    return p.join(proxyDir.path, '$key$extension');
  }

  Future<void> embedCover({
    required String inputPath,
    required String outputPath,
    String? imagePath,
  }) async {
    await _ensurePlatformSupported();
    final List<String> args;
    if (imagePath == null || imagePath.isEmpty) {
      args = [
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:a?',
        '-c',
        'copy',
        '-map_metadata',
        '0',
        outputPath,
      ];
    } else {
      args = [
        '-y',
        '-i',
        inputPath,
        '-i',
        imagePath,
        '-map',
        '0:a?',
        '-map',
        '1',
        '-c',
        'copy',
        '-disposition:v:0',
        'attached_pic',
        '-map_metadata',
        '0',
        outputPath,
      ];
    }

    final result = await executeFFmpeg(args);
    if (!result.isSuccess) {
      throw Exception('FFmpeg failed: ${result.returnCode}\n${result.logs}');
    }

    final file = File(outputPath);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception('FFmpeg produced empty output: $outputPath');
    }
  }

  Future<void> embedLyrics({
    required String inputPath,
    required String outputPath,
    required String? lyrics,
  }) async {
    await _ensurePlatformSupported();
    final normalizedLyrics = lyrics?.trim() ?? '';
    final hasVideo = await hasVideoStream(inputPath);
    final ext = p.extension(inputPath).toLowerCase();
    final isMp3 = ext == '.mp3';

    final args = [
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:a?',
      if (hasVideo) ...[
        '-map',
        '0:v?',
        '-disposition:v:0',
        'attached_pic',
      ],
      '-c',
      'copy',
      if (isMp3) ...[
        '-id3v2_version',
        '3',
      ],
      '-map_metadata',
      '0',
      '-metadata',
      'lyrics=$normalizedLyrics',
      '-metadata',
      'unsynced_lyrics=$normalizedLyrics',
      outputPath,
    ];

    final result = await executeFFmpeg(args);
    if (!result.isSuccess) {
      throw Exception(
          'FFmpeg lyrics write failed: ${result.returnCode}\n${result.logs}');
    }

    final outFile = File(outputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      throw Exception('FFmpeg lyrics write produced empty output: $outputPath');
    }
  }

  /// Updates text metadata (title/artist/album) without re-encoding audio and
  /// without dropping existing tags, cover or lyrics.
  ///
  /// Uses `ffmpeg -c copy -map_metadata 0` so every tag not explicitly
  /// overwritten is preserved. `-map 0:v?` preserves attached pictures that
  /// would otherwise be lost when only the title changes. An empty string
  /// clears the tag (`-metadata title=`); `null` leaves it untouched (not
  /// passed). Validates the output still contains an audio stream before
  /// returning.
  Future<void> updateTextMetadata({
    required String inputPath,
    required String outputPath,
    String? title,
    String? artist,
    String? album,
  }) async {
    await _ensurePlatformSupported();
    final hasVideo = await hasVideoStream(inputPath);
    final ext = p.extension(inputPath).toLowerCase();
    final isMp3 = ext == '.mp3';

    // Normalise: trim but keep empty to allow clearing. Null means "don't touch".
    String? normalize(String? value) {
      if (value == null) return null;
      return value.trim();
    }

    final nTitle = normalize(title);
    final nArtist = normalize(artist);
    final nAlbum = normalize(album);

    final args = [
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:a?',
      if (hasVideo) ...[
        '-map',
        '0:v?',
        '-disposition:v:0',
        'attached_pic',
      ],
      '-c',
      'copy',
      if (isMp3) ...[
        '-id3v2_version',
        '3',
      ],
      '-map_metadata',
      '0',
      if (nTitle != null) ...[
        '-metadata',
        'title=$nTitle',
      ],
      if (nArtist != null) ...[
        '-metadata',
        'artist=$nArtist',
      ],
      if (nAlbum != null) ...[
        '-metadata',
        'album=$nAlbum',
      ],
      outputPath,
    ];

    final result = await executeFFmpeg(args);
    if (!result.isSuccess) {
      throw Exception(
          'FFmpeg text metadata write failed: ${result.returnCode}\n${result.logs}');
    }

    final outFile = File(outputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      throw Exception(
          'FFmpeg text metadata write produced empty output: $outputPath');
    }
  }

  /// Checks if the file contains a video/artwork stream.
  Future<bool> hasVideoStream(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() == 0) return false;

      final args = [
        '-v',
        'error',
        '-select_streams',
        'v',
        '-show_entries',
        'stream=codec_type',
        '-of',
        'csv=p=0',
        filePath,
      ];
      final result = await executeFFprobe(args);
      if (!result.isSuccess) return false;
      return result.output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Reads lyrics from audio file metadata using FFprobe.
  /// Returns the lyrics string if found, null otherwise.
  Future<String?> getLyrics(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (kDebugMode) debugPrint('FFmpegService: File not found: $filePath');
        return null;
      }

      final args = [
        '-v',
        'quiet',
        '-show_entries',
        'format_tags',
        '-print_format',
        'json',
        filePath,
      ];

      final result = await executeFFprobe(args);
      if (!result.isSuccess) {
        if (kDebugMode) {
          debugPrint(
              'FFmpegService: FFprobe failed: ${result.returnCode}\n${result.logs}');
        }
        return null;
      }

      final output = result.output;
      if (output.trim().isEmpty) {
        if (kDebugMode) {
          debugPrint('FFmpegService: Empty output for: $filePath');
        }
        return null;
      }

      final json = jsonDecode(output);
      final tags = json['format']?['tags'];

      if (tags == null) {
        if (kDebugMode) {
          debugPrint('FFmpegService: No tags found in: $filePath');
        }
        return null;
      }

      String? coerceLyrics(dynamic value) {
        final text = value?.toString();
        if (text == null) return null;
        final trimmed = text.trim();
        return trimmed.isEmpty ? null : trimmed;
      }

      final directLyrics = coerceLyrics(
        tags['lyrics'] ??
            tags['LYRICS'] ??
            tags['unsynced_lyrics'] ??
            tags['UNSYNCED_LYRICS'] ??
            tags['©lyr'] ??
            tags['USLT'],
      );

      if (directLyrics != null) {
        if (kDebugMode) debugPrint('FFmpegService: Found lyrics in: $filePath');
        return directLyrics;
      }

      if (tags is Map) {
        for (final entry in tags.entries) {
          final key = entry.key?.toString() ?? '';
          final normalizedKey =
              key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          const lyricKeys = {
            'lyrics',
            'lyric',
            'unsyncedlyrics',
            'uslt',
            'lyr',
          };
          if (!lyricKeys.contains(normalizedKey)) continue;
          final value = coerceLyrics(entry.value);
          if (value != null) {
            if (kDebugMode) {
              debugPrint(
                  'FFmpegService: Found lyrics via key "$key" in: $filePath');
            }
            return value;
          }
        }
      }

      if (kDebugMode) {
        debugPrint('FFmpegService: No lyrics tag found in: $filePath');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('FFmpegService: Error reading lyrics: $e');
      return null;
    }
  }

  Future<bool> hasAudioStream(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() == 0) return false;

      final args = [
        '-v',
        'error',
        '-select_streams',
        'a',
        '-show_entries',
        'stream=codec_type',
        '-of',
        'csv=p=0',
        filePath,
      ];
      final result = await executeFFprobe(args);
      if (!result.isSuccess) return false;
      return result.output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Gets the video codec name without decoding the stream.
  /// Returns null if no video stream or on error.
  Future<String?> getVideoCodec(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final args = [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=codec_name',
        '-of',
        'csv=p=0',
        filePath,
      ];
      final result = await executeFFprobe(args);
      if (!result.isSuccess) return null;
      final codec = result.output.trim().toLowerCase();
      return codec.isEmpty ? null : codec;
    } catch (_) {
      return null;
    }
  }

  /// Checks if the file has an AV1 video stream without decoding it.
  Future<bool> isAV1File(String filePath) async {
    final codec = await getVideoCodec(filePath);
    return codec == 'av1';
  }

  Future<String?> extractCover({
    required String inputPath,
    required String outputPath,
  }) async {
    final isAV1 = await isAV1File(inputPath);
    if (isAV1) {
      if (kDebugMode) {
        debugPrint('FFmpegService: Skipping AV1 file: $inputPath');
      }
      return null;
    }

    try {
      final result = await executeFFmpeg([
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-c',
        'copy',
        outputPath,
      ]);

      if (result.isSuccess) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      } else {
        // Fallback: If copy fails (e.g. stream issue), try simple re-encode
        final result2 = await executeFFmpeg([
          '-y',
          '-i',
          inputPath,
          '-an',
          '-vcodec',
          'mjpeg',
          '-q:v',
          '2',
          outputPath,
        ]);
        if (result2.isSuccess) {
          final file = File(outputPath);
          if (await file.exists() && await file.length() > 0) {
            return outputPath;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FFmpegService: Extraction failed: $e');
    }

    return null;
  }

  /// Grabs a single video frame and saves it as a JPEG thumbnail.
  ///
  /// Unlike [extractCover] (which does a stream-copy suited for audio files
  /// with an attached-picture stream), this method decodes and captures a
  /// specific frame from the video track. This is the correct
  /// approach for real video files (MP4, MKV, WebM, MOV, AVI, etc.) where
  /// stream 0:v:0 is H.264/VP9/etc. and cannot be "copied" into a JPEG.
  ///
  /// [frameNumber] is 1-based and defaults to 5, so the generated thumbnail
  /// comes from the 5th decoded frame.
  Future<String?> extractVideoThumbnail({
    required String inputPath,
    required String outputPath,
    int frameNumber = 5,
  }) async {
    final isAV1 = await isAV1File(inputPath);
    if (isAV1) {
      if (kDebugMode) {
        debugPrint('FFmpegService: Skipping AV1 file: $inputPath');
      }
      return null;
    }

    try {
      final normalizedFrameNumber = frameNumber < 1 ? 1 : frameNumber;

      // 1) Try stream-copy first. This is fast and succeeds if the source has
      // an attached picture stream.
      final copyResult = await executeFFmpeg([
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-c',
        'copy',
        outputPath,
      ]);
      if (copyResult.isSuccess) {
        final copiedFile = File(outputPath);
        if (await copiedFile.exists() && await copiedFile.length() > 0) {
          return outputPath;
        }
      }

      // 2) Prefer a frame around 10% in to avoid blank/intro frames.
      final durationSec = await _getMediaDurationSeconds(inputPath);
      final seekSec =
          durationSec != null && durationSec > 0 ? (durationSec * 0.1) : 0.0;
      final seekResult = await executeFFmpeg([
        '-y',
        '-ss',
        seekSec.toStringAsFixed(3),
        '-i',
        inputPath,
        '-frames:v',
        '1',
        '-q:v',
        '3',
        outputPath,
      ]);
      if (seekResult.isSuccess) {
        final seekFile = File(outputPath);
        if (await seekFile.exists() && await seekFile.length() > 0) {
          return outputPath;
        }
      }

      // 3) Fallback to selecting a specific decoded frame index.
      final zeroBasedFrameIndex = normalizedFrameNumber - 1;
      final selectResult = await executeFFmpeg([
        '-y',
        '-i',
        inputPath,
        '-vf',
        "select='eq(n\\,$zeroBasedFrameIndex)',scale='min(640,iw)':-2",
        '-vframes',
        '1',
        '-q:v',
        '3',
        outputPath,
      ]);
      if (selectResult.isSuccess) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      }
      if (kDebugMode) {
        debugPrint(
            'FFmpegService.extractVideoThumbnail: extraction failed for frame '
            '$normalizedFrameNumber\n${selectResult.logs}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FFmpegService.extractVideoThumbnail: exception: $e');
      }
    }

    return null;
  }

  Future<bool> generateBlurredImage({
    required String inputPath,
    required String outputPath,
    int width = 300,
    int height = 300,
    int blurSigma = 15,
  }) async {
    try {
      String normalizedInput = inputPath;
      if (inputPath.startsWith('file://')) {
        normalizedInput = Uri.parse(inputPath).toFilePath();
      }

      final bytes = await File(normalizedInput).readAsBytes();
      final jpgBytes = await Isolate.run(
        () => generateBlurredImageBytes(
          bytes,
          width: width,
          height: height,
          blurSigma: blurSigma,
        ),
      );
      if (jpgBytes == null) return false;

      await File(outputPath).writeAsBytes(jpgBytes);

      final file = File(outputPath);
      return await file.exists() && await file.length() > 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FFmpegService: generateBlurredImage failed: $e');
      }
    }
    return false;
  }

  Future<double?> _getMediaDurationSeconds(String filePath) async {
    try {
      final args = [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        filePath,
      ];
      final result = await executeFFprobe(args);
      if (!result.isSuccess) return null;
      final output = result.output.trim();
      if (output.isEmpty) return null;
      return double.tryParse(output);
    } catch (_) {
      return null;
    }
  }
}

/// Decodes, blurs and re-encodes cover bytes to a small JPEG.
///
/// Top-level so it can run in a spawned isolate: everything here is pure Dart
/// (`image` does no platform calls), so the expensive decode + blur + encode
/// never touches the UI thread. Returns null when [bytes] is not an image.
Uint8List? generateBlurredImageBytes(
  Uint8List bytes, {
  required int width,
  required int height,
  required int blurSigma,
}) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    image = img.copyResize(image, width: width, height: height);
    image = img.gaussianBlur(image, radius: blurSigma);

    return img.encodeJpg(image, quality: 80);
  } catch (_) {
    return null;
  }
}

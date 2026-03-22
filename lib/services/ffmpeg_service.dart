import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

class FFmpegService {
  Future<void> embedCover({
    required String inputPath,
    required String outputPath,
    String? imagePath,
  }) async {
    final List<String> args;
    if (imagePath == null || imagePath.isEmpty) {
      // Remove attached picture streams, keep audio + metadata.
      args = [
        '-y',
        '-i', inputPath,
        '-map', '0:a?', // Safely map all audio streams
        '-c', 'copy',
        '-map_metadata', '0',
        outputPath,
      ];
    } else {
      // Add/replace cover art as attached picture mirroring Namida's method.
      // 1. Map all audio from first input (0:a?)
      // 2. Map the image from second input (1)
      // 3. Mark the image as 'attached_pic'
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

    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg failed: $rc\n$logs');
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
    final normalizedLyrics = lyrics?.trim() ?? '';
    final args = [
      '-y',
      '-i',
      inputPath,
      '-map',
      '0',
      '-c',
      'copy',
      '-map_metadata',
      '0',
      '-metadata',
      'lyrics=$normalizedLyrics',
      '-metadata',
      'unsynced_lyrics=$normalizedLyrics',
      outputPath,
    ];

    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg lyrics write failed: $rc\n$logs');
    }

    final outFile = File(outputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      throw Exception('FFmpeg lyrics write produced empty output: $outputPath');
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

      final input = _q(filePath);
      final cmd =
          '-v quiet -show_entries format_tags -print_format json $input';

      final session = await FFprobeKit.execute(cmd);
      final rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc)) {
        final logs = await session.getAllLogsAsString();
        if (kDebugMode) debugPrint('FFmpegService: FFprobe failed: $rc\n$logs');
        return null;
      }

      final output = await session.getOutput();
      if (output == null || output.isEmpty) {
        if (kDebugMode) {
          debugPrint('FFmpegService: Empty output for: $filePath');
        }
        return null;
      }

      // Parse JSON output
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

      final input = _q(filePath);
      final cmd =
          '-v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $input';
      final session = await FFprobeKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) return false;
      final output = await session.getOutput();
      return output != null && output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> extractCover({
    required String inputPath,
    required String outputPath,
  }) async {
    // Optimized: Stream copy mirroring Namida's extraction logic
    try {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-c',
        'copy',
        outputPath,
      ]);
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      } else {
        // Fallback: If copy fails (e.g. stream issue), try simple re-encode
        final session2 = await FFmpegKit.executeWithArguments([
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
        final rc2 = await session2.getReturnCode();
        if (ReturnCode.isSuccess(rc2)) {
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
    try {
      final normalizedFrameNumber = frameNumber < 1 ? 1 : frameNumber;

      // 1) Try stream-copy first. This is fast and succeeds if the source has
      // an attached picture stream.
      final copySession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-c',
        'copy',
        outputPath,
      ]);
      final copyRc = await copySession.getReturnCode();
      if (ReturnCode.isSuccess(copyRc)) {
        final copiedFile = File(outputPath);
        if (await copiedFile.exists() && await copiedFile.length() > 0) {
          return outputPath;
        }
      }

      // 2) Prefer a frame around 10% in to avoid blank/intro frames.
      final durationSec = await _getMediaDurationSeconds(inputPath);
      final seekSec =
          durationSec != null && durationSec > 0 ? (durationSec * 0.1) : 0.0;
      final seekSession = await FFmpegKit.executeWithArguments([
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
      final seekRc = await seekSession.getReturnCode();
      if (ReturnCode.isSuccess(seekRc)) {
        final seekFile = File(outputPath);
        if (await seekFile.exists() && await seekFile.length() > 0) {
          return outputPath;
        }
      }

      // 3) Fallback to selecting a specific decoded frame index.
      final zeroBasedFrameIndex = normalizedFrameNumber - 1;
      final selectSession = await FFmpegKit.executeWithArguments([
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
      final selectRc = await selectSession.getReturnCode();
      if (ReturnCode.isSuccess(selectRc)) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      }
      if (kDebugMode) {
        final logs2 = await selectSession.getAllLogsAsString();
        debugPrint(
            'FFmpegService.extractVideoThumbnail: extraction failed for frame '
            '$normalizedFrameNumber\n$logs2');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FFmpegService.extractVideoThumbnail: exception: $e');
      }
    }

    return null;
  }

  Future<double?> _getMediaDurationSeconds(String filePath) async {
    try {
      final input = _q(filePath);
      final cmd =
          '-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $input';
      final session = await FFprobeKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) return null;
      final output = await session.getOutput();
      if (output == null) return null;
      return double.tryParse(output.trim());
    } catch (_) {
      return null;
    }
  }

  String _q(String path) {
    final escaped = path.replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

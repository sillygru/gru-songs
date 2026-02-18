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

      // Check for lyrics tag (could be 'lyrics', 'LYRICS', or 'unsynced_lyrics')
      final lyrics =
          tags['lyrics'] ?? tags['LYRICS'] ?? tags['unsynced_lyrics'];

      if (lyrics != null && lyrics.toString().isNotEmpty) {
        if (kDebugMode) debugPrint('FFmpegService: Found lyrics in: $filePath');
        return lyrics.toString();
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
  /// with an attached-picture stream), this method seeks to [seekSeconds] and
  /// decodes exactly one frame from the video track.  This is the correct
  /// approach for real video files (MP4, MKV, WebM, MOV, AVI, etc.) where
  /// stream 0:v:0 is H.264/VP9/etc. and cannot be "copied" into a JPEG.
  ///
  /// [seekSeconds] defaults to 5 s.  If the file is shorter the seek is
  /// clamped to 0 by FFmpeg automatically, so it is safe to use this value
  /// unconditionally.
  Future<String?> extractVideoThumbnail({
    required String inputPath,
    required String outputPath,
    double seekSeconds = 5.0,
  }) async {
    try {
      // Input-side seek (-ss before -i) is fast: FFmpeg jumps to the nearest
      // keyframe before seekSeconds without decoding every prior frame.
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss', seekSeconds.toStringAsFixed(3),
        '-i', inputPath,
        '-vframes', '1', // exactly one output frame
        '-q:v', '3', // JPEG quality 1–31, lower = better
        '-vf', 'scale=\'min(640,iw)\':-2', // cap width at 640 px, keep AR
        outputPath,
      ]);

      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      }

      // Fallback: seek at 0 (in case the file is very short or the keyframe
      // at 5 s is unavailable).
      if (kDebugMode) {
        final logs = await session.getAllLogsAsString();
        debugPrint(
            'FFmpegService.extractVideoThumbnail: seek@${seekSeconds}s failed, '
            'retrying at 0\n$logs');
      }

      final session2 = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        inputPath,
        '-vframes',
        '1',
        '-q:v',
        '3',
        '-vf',
        'scale=\'min(640,iw)\':-2',
        outputPath,
      ]);

      final rc2 = await session2.getReturnCode();
      if (ReturnCode.isSuccess(rc2)) {
        final file = File(outputPath);
        if (await file.exists() && await file.length() > 0) {
          return outputPath;
        }
      }

      if (kDebugMode) {
        final logs2 = await session2.getAllLogsAsString();
        debugPrint(
            'FFmpegService.extractVideoThumbnail: fallback also failed\n$logs2');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FFmpegService.extractVideoThumbnail: exception: $e');
      }
    }

    return null;
  }

  String _q(String path) {
    final escaped = path.replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

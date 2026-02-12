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
    final input = _q(inputPath);
    final output = _q(outputPath);

    final String cmd;
    if (imagePath == null || imagePath.isEmpty) {
      // Remove attached picture streams, keep audio + metadata.
      cmd = '-y -i $input -map 0:a -c copy -map_metadata 0 '
          '-movflags use_metadata_tags $output';
    } else {
      final image = _q(imagePath);
      // Add/replace cover art as attached picture.
      cmd = '-y -i $input -i $image '
          '-map 0:a -map 1:v '
          '-c copy -map_metadata 0 '
          '-disposition:v:0 attached_pic '
          '-metadata:s:v title="Album cover" '
          '-metadata:s:v comment="Cover (front)" '
          '-movflags use_metadata_tags $output';
    }

    final session = await FFmpegKit.execute(cmd);
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
        if (kDebugMode)
          debugPrint('FFmpegService: Empty output for: $filePath');
        return null;
      }

      // Parse JSON output
      final json = jsonDecode(output);
      final tags = json['format']?['tags'];

      if (tags == null) {
        if (kDebugMode)
          debugPrint('FFmpegService: No tags found in: $filePath');
        return null;
      }

      // Check for lyrics tag (could be 'lyrics', 'LYRICS', or 'unsynced_lyrics')
      final lyrics =
          tags['lyrics'] ?? tags['LYRICS'] ?? tags['unsynced_lyrics'];

      if (lyrics != null && lyrics.toString().isNotEmpty) {
        if (kDebugMode) debugPrint('FFmpegService: Found lyrics in: $filePath');
        return lyrics.toString();
      }

      if (kDebugMode)
        debugPrint('FFmpegService: No lyrics tag found in: $filePath');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('FFmpegService: Error reading lyrics: $e');
      return null;
    }
  }

  String _q(String path) {
    final escaped = path.replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

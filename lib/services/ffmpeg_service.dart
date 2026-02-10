import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
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

  String _q(String path) {
    final escaped = path.replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

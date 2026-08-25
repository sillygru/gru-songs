import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/ffmpeg_service.dart';

void main() {
  group('FFmpegService', () {
    test('FFmpegExecutionResult properties work as expected', () {
      const success = FFmpegExecutionResult(
        returnCode: 0,
        output: 'ok',
        logs: '',
      );
      expect(success.isSuccess, isTrue);
      expect(success.output, 'ok');

      const failure = FFmpegExecutionResult(
        returnCode: 1,
        output: '',
        logs: 'error',
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.logs, 'error');
    });

    test('can check ffmpeg and ffprobe availability', () async {
      final ffmpeg = FFmpegService();
      final hasFfmpeg = await ffmpeg.isFFmpegAvailable();
      final hasFfprobe = await ffmpeg.isFFprobeAvailable();

      expect(hasFfmpeg, isA<bool>());
      expect(hasFfprobe, isA<bool>());
    });

    test('executes -version without crashing', () async {
      final ffmpeg = FFmpegService();
      if (await ffmpeg.isFFmpegAvailable()) {
        final result = await ffmpeg.executeFFmpeg(['-version']);
        expect(result.isSuccess, isTrue);
        expect(result.returnCode, 0);
      }
      if (await ffmpeg.isFFprobeAvailable()) {
        final probeResult = await ffmpeg.executeFFprobe(['-version']);
        expect(probeResult.isSuccess, isTrue);
        expect(probeResult.returnCode, 0);
      }
    });

    test('gracefully handles missing input files', () async {
      final ffmpeg = FFmpegService();
      final lyrics = await ffmpeg.getLyrics('/nonexistent/path/song.mp3');
      expect(lyrics, isNull);

      final hasVideo =
          await ffmpeg.hasVideoStream('/nonexistent/path/song.mp3');
      expect(hasVideo, isFalse);

      final hasAudio =
          await ffmpeg.hasAudioStream('/nonexistent/path/song.mp3');
      expect(hasAudio, isFalse);
    });
  });
}

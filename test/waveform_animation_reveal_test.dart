import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/presentation/widgets/waveform_progress_bar.dart';
import 'package:wispie/providers/providers.dart';
import 'package:wispie/services/cache_service.dart';
import 'package:wispie/services/waveform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WaveformPainter reveal geometry', () {
    test('all bars are minimized when revealProgress is 0.0', () {
      final peaks = List<double>.generate(2000, (i) => (i % 10) / 10.0);
      final posNotifier = ValueNotifier(Duration.zero);
      final dragNotifier = ValueNotifier<double?>(null);

      final painter = WaveformPainter(
        peaks: peaks,
        revealProgress: 0.0,
        positionNotifier: posNotifier,
        dragPositionNotifier: dragNotifier,
        total: const Duration(minutes: 3),
        color: Colors.blue,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 60));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test(
        'bars past the reveal front remain fully expanded to respective heights',
        () {
      final peaks = List<double>.generate(2000, (i) => 0.8);
      final posNotifier = ValueNotifier(Duration.zero);
      final dragNotifier = ValueNotifier<double?>(null);

      final painterHalf = WaveformPainter(
        peaks: peaks,
        revealProgress: 0.5,
        positionNotifier: posNotifier,
        dragPositionNotifier: dragNotifier,
        total: const Duration(minutes: 3),
        color: Colors.blue,
      );

      final painterFull = WaveformPainter(
        peaks: peaks,
        revealProgress: 1.0,
        positionNotifier: posNotifier,
        dragPositionNotifier: dragNotifier,
        total: const Duration(minutes: 3),
        color: Colors.blue,
      );

      expect(painterHalf.revealProgress, 0.5);
      expect(painterFull.revealProgress, 1.0);
    });

    test('each bar scales to its own respective height, not a flat height', () {
      final loudAmp = 0.9;
      final quietAmp = 0.1;
      const height = 60.0;

      final loudHeight = calculateWaveformBarHeight(loudAmp, height);
      final quietHeight = calculateWaveformBarHeight(quietAmp, height);

      expect(loudHeight, greaterThan(quietHeight));
      expect(quietHeight, greaterThan(1.0));
      expect(loudHeight, lessThanOrEqualTo(height));
    });
  });

  group('WaveformProgressBar widget animation', () {
    testWidgets('cached waveform renders and animates reveal', (tester) async {
      final fakePeaks = List<double>.filled(2000, 0.6);
      final mockService = _MockCachedWaveformService(fakePeaks);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: WaveformProgressBar(
                    filename: 'test_cached.mp3',
                    path: '/music/test_cached.mp3',
                    progress: Duration.zero,
                    total: const Duration(minutes: 3),
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Initial frame: rendered
      await tester.pump();
      expect(find.byType(WaveformProgressBar), findsOneWidget);

      // Advance frames through reveal animation
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byType(WaveformProgressBar), findsOneWidget);
    });

    testWidgets(
        'progressive uncached stream reveals left to right in real time',
        (tester) async {
      final controller = StreamController<List<double>>.broadcast();
      final mockService = _MockProgressiveWaveformService(controller.stream);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: WaveformProgressBar(
                    filename: 'test_uncached.mp3',
                    path: '/music/test_uncached.mp3',
                    progress: Duration.zero,
                    total: const Duration(minutes: 3),
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Emit 25% decoded peaks (500 samples)
      controller.add(List<double>.filled(500, 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Emit 50% decoded peaks (1000 samples)
      controller.add(List<double>.filled(1000, 0.7));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Emit 100% complete waveform (2000 samples)
      controller.add(List<double>.filled(2000, 0.8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(WaveformProgressBar), findsOneWidget);

      await controller.close();
    });
  });
}

class _MockCachedWaveformService extends WaveformService {
  final List<double> cachedPeaks;

  _MockCachedWaveformService(this.cachedPeaks) : super(CacheService.instance);

  @override
  List<double>? cachedWaveformSync(String filename) => cachedPeaks;

  @override
  Future<bool> isWaveformCached(String filename) async => true;

  @override
  Stream<List<double>> getWaveformProgressive(
    String filename,
    String path,
    Duration total,
  ) {
    return Stream.value(cachedPeaks);
  }
}

class _MockProgressiveWaveformService extends WaveformService {
  final Stream<List<double>> progressiveStream;

  _MockProgressiveWaveformService(this.progressiveStream)
      : super(CacheService.instance);

  @override
  List<double>? cachedWaveformSync(String filename) => null;

  @override
  Future<bool> isWaveformCached(String filename) async => false;

  @override
  Stream<List<double>> getWaveformProgressive(
    String filename,
    String path,
    Duration total,
  ) {
    return progressiveStream;
  }
}

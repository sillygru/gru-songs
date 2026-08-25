import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/presentation/widgets/waveform_progress_bar.dart';
import 'package:wispie/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Waveform Haptics Settings', () {
    test('defaults to true and persists changes', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      expect(container.read(settingsProvider).waveformHapticsEnabled, isTrue);

      await notifier.setWaveformHapticsEnabled(false);
      expect(container.read(settingsProvider).waveformHapticsEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('waveform_haptics_enabled'), isFalse);

      await notifier.setWaveformHapticsEnabled(true);
      expect(container.read(settingsProvider).waveformHapticsEnabled, isTrue);
      expect(prefs.getBool('waveform_haptics_enabled'), isTrue);
    });
  });

  group('WaveformProgressBar Haptics', () {
    final hapticCalls = <MethodCall>[];

    setUp(() {
      hapticCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          hapticCalls.add(call);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('triggers selectionClick haptics when dragging across bars',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'waveform_haptics_enabled': true,
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: WaveformProgressBar(
                    filename: 'test.mp3',
                    path: '/path/test.mp3',
                    progress: Duration.zero,
                    total: const Duration(seconds: 180),
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final waveformFinder = find.byType(WaveformProgressBar);
      expect(waveformFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(waveformFinder);

      final gesture = await tester.startGesture(topLeft + const Offset(10, 20));
      await tester.pump();

      // Drag across several bars (exceeding slop and traversing bars)
      for (var offset = 10.0; offset <= 80.0; offset += 5.0) {
        await gesture.moveTo(topLeft + Offset(offset, 20));
        await tester.pump();
      }

      await gesture.up();
      await tester.pump();

      expect(hapticCalls, isNotEmpty);
      expect(
        hapticCalls.every(
            (call) => call.arguments == 'HapticFeedbackType.selectionClick'),
        isTrue,
      );
    });

    testWidgets('stays silent when waveform haptics setting is disabled',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'waveform_haptics_enabled': false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(settingsProvider.notifier)
          .setWaveformHapticsEnabled(false);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: WaveformProgressBar(
                    filename: 'test2.mp3',
                    path: '/path/test2.mp3',
                    progress: Duration.zero,
                    total: const Duration(seconds: 180),
                    onSeek: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final waveformFinder = find.byType(WaveformProgressBar);
      final topLeft = tester.getTopLeft(waveformFinder);

      final gesture = await tester.startGesture(topLeft + const Offset(10, 20));
      await tester.pump();

      for (var offset = 10.0; offset <= 80.0; offset += 5.0) {
        await gesture.moveTo(topLeft + Offset(offset, 20));
        await tester.pump();
      }

      await gesture.up();
      await tester.pump();

      expect(hapticCalls, isEmpty);
    });
  });
}

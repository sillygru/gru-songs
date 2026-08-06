import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/services/cache_service.dart';
import 'package:wispie/services/waveform_service.dart';

import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  group('waveform memory cache', () {
    test('a cached song is served from memory on a later open', () async {
      final cacheService = CacheService.instance;
      await cacheService.init();
      final service = WaveformService(cacheService);

      const filename = '/music/song.mp3';
      const samples = [0.1, 0.5, 0.9, 0.4];

      // Simulate a waveform that was previously computed and cached on disk.
      final cacheFile = await cacheService.getWaveformCacheFile(filename);
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(jsonEncode(samples));

      // First open reads the disk-backed cache and populates the memory map.
      final first = await service
          .getWaveformProgressive(filename, filename, Duration.zero)
          .first;
      expect(first, samples);
      expect(service.cachedWaveformSync(filename), samples);

      // A later open in the same session is served synchronously from memory,
      // short-circuiting the async/disk path entirely.
      final second = await service
          .getWaveformProgressive(filename, filename, Duration.zero)
          .first;
      expect(second, samples);
    });

    test('isWaveformCached stays true from memory after the disk file is gone',
        () async {
      final cacheService = CacheService.instance;
      await cacheService.init();
      final service = WaveformService(cacheService);

      const filename = '/music/mem.mp3';
      const samples = [0.2, 0.6];

      final cacheFile = await cacheService.getWaveformCacheFile(filename);
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(jsonEncode(samples));

      await service
          .getWaveformProgressive(filename, filename, Duration.zero)
          .first;
      expect(service.cachedWaveformSync(filename), samples);

      // Delete the disk file; the memory entry keeps the check truthful.
      await cacheFile.delete();
      expect(await service.isWaveformCached(filename), isTrue);
    });
  });
}

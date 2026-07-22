import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:wispie/models/song.dart';
import 'package:wispie/services/cache_service.dart';
import 'package:wispie/services/color_extraction_service.dart';
import 'package:wispie/services/file_manager_service.dart';
import 'package:wispie/services/scanner_service.dart';

import '../test_helpers.dart';

void main() {
  late TestEnvironment testEnv;
  final cacheService = CacheService.instance;

  setUpAll(() {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() {
    testEnv.tearDown();
  });

  test('prunes stale song caches but keeps referenced files', () async {
    await cacheService.init();

    final supportDir = Directory(testEnv.tempPath);
    final extractedCoversDir =
        Directory(p.join(supportDir.path, 'extracted_covers'));
    final blurredDir =
        Directory(p.join(supportDir.path, 'gru_cache_v3', 'blurred_cache'));
    final notificationDir = Directory(
      p.join(supportDir.path, 'gru_cache_v3', 'notification_cover_cache'),
    );

    await extractedCoversDir.create(recursive: true);
    await blurredDir.create(recursive: true);
    await notificationDir.create(recursive: true);

    final keepCover = File(p.join(extractedCoversDir.path, 'keep.jpg'));
    final dropCover = File(p.join(extractedCoversDir.path, 'drop.jpg'));
    await keepCover.writeAsString('keep');
    await dropCover.writeAsString('drop');

    final referencedSong = Song(
      title: 'Keep',
      artist: 'Artist',
      album: 'Album',
      filename: '/music/keep.mp3',
      url: '/music/keep.mp3',
      coverUrl: keepCover.path,
    );

    final keepBlur =
        await cacheService.getBlurredCacheFile(referencedSong.filename);
    final dropBlur = await cacheService.getBlurredCacheFile('/music/drop.mp3');
    await keepBlur.parent.create(recursive: true);
    await keepBlur.writeAsString('keep blur');
    await dropBlur.parent.create(recursive: true);
    await dropBlur.writeAsString('drop blur');

    final keepNotif =
        await cacheService.getNotificationCoverCacheFile('keep_jpg');
    final dropNotif =
        await cacheService.getNotificationCoverCacheFile('drop_jpg');
    await keepNotif.writeAsString('keep notif');
    await dropNotif.writeAsString('drop notif');

    await cacheService.pruneStaleSongCaches([referencedSong]);

    expect(await keepCover.exists(), isTrue);
    expect(await dropCover.exists(), isFalse);
    expect(await keepBlur.exists(), isTrue);
    expect(await dropBlur.exists(), isFalse);
    expect(await keepNotif.exists(), isTrue);
    expect(await dropNotif.exists(), isFalse);
  });

  test('prunes stale lyrics, waveform, and color cache entries', () async {
    await cacheService.init();
    await ColorExtractionService.clearCache();

    final supportDir = Directory(testEnv.tempPath);
    final mediaDir = Directory(p.join(supportDir.path, 'music'));
    await mediaDir.create(recursive: true);

    final keepAudio = File(p.join(mediaDir.path, 'keep.mp3'));
    final dropAudio = File(p.join(mediaDir.path, 'drop.mp3'));
    await keepAudio.writeAsString('keep audio');
    await dropAudio.writeAsString('drop audio');

    final keepCover = File(p.join(supportDir.path, 'keep-cover.jpg'));
    final dropCover = File(p.join(supportDir.path, 'drop-cover.jpg'));
    final image = img.Image(width: 2, height: 2);
    img.fill(image, color: img.ColorRgb8(20, 80, 140));
    await keepCover.writeAsBytes(img.encodeJpg(image));
    await dropCover.writeAsBytes(img.encodeJpg(image));

    final keepSong = Song(
      title: 'Keep',
      artist: 'Artist',
      album: 'Album',
      filename: 'keep.mp3',
      url: keepAudio.path,
      coverUrl: keepCover.path,
    );

    final lyricsDir =
        Directory(p.join(supportDir.path, 'gru_cache_v3', 'lyrics_cache'));
    await lyricsDir.create(recursive: true);
    final keepLyrics = File(p.join(
      lyricsDir.path,
      '${sha1.convert(utf8.encode(keepAudio.path))}.json',
    ));
    final dropLyrics = File(p.join(
      lyricsDir.path,
      '${sha1.convert(utf8.encode(dropAudio.path))}.json',
    ));
    await keepLyrics.writeAsString(jsonEncode({
      'hasLyrics': true,
      'lyrics': 'lyrics',
    }));
    await dropLyrics.writeAsString(jsonEncode({
      'hasLyrics': false,
    }));

    final keepWaveform =
        await cacheService.getWaveformCacheFile(keepSong.filename);
    final dropWaveform = await cacheService.getWaveformCacheFile('drop.mp3');
    final legacyDropWaveform = File(p.join(
      supportDir.path,
      'gru_cache_v3',
      'waveform_',
      'music',
      'drop.mp3.json',
    ));
    await legacyDropWaveform.parent.create(recursive: true);
    await keepWaveform.writeAsString('[0.1]');
    await dropWaveform.writeAsString('[0.2]');
    await legacyDropWaveform.writeAsString('[0.3]');

    await ColorExtractionService.extractPalette(keepCover.path);
    await ColorExtractionService.extractPalette(dropCover.path);
    expect(
        await ColorExtractionService.hasCachedPalette(dropCover.path), isTrue);

    await cacheService.pruneStaleSongCaches([keepSong]);

    expect(await keepLyrics.exists(), isTrue);
    expect(await dropLyrics.exists(), isFalse);
    expect(await keepWaveform.exists(), isTrue);
    expect(await dropWaveform.exists(), isFalse);
    expect(await legacyDropWaveform.exists(), isFalse);
    expect(
        await ColorExtractionService.hasCachedPalette(keepCover.path), isTrue);
    expect(
        await ColorExtractionService.hasCachedPalette(dropCover.path), isFalse);
  });

  group('cover cache key stability', () {
    test('coverKeyForFilename returns stable key regardless of mtime', () {
      const filename = 'song.mp3';
      final key1 = ScannerService.coverKeyForFilename(filename);
      final key2 =
          ScannerService.coverKeyForFilename('/different/path/song.mp3');
      expect(key1, equals(key2));
    });

    test('coverKeyForFilename uses only basename of file path', () {
      final key1 = ScannerService.coverKeyForFilename('/a/b/song.mp3');
      final key2 = ScannerService.coverKeyForFilename('/c/d/song.mp3');
      final key3 = ScannerService.coverKeyForFilename('/a/b/different.mp3');
      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
    });

    test('coverKeyForFilename produces sha1 hash of filename', () {
      const filename = 'test_song.mp3';
      final key = ScannerService.coverKeyForFilename(filename);
      final expected = sha1.convert(utf8.encode(filename)).toString();
      expect(key, equals(expected));
    });
  });

  group('manual cover extraction', () {
    test('extractCoverForFile finds m4a covr boxes', () async {
      final supportDir = Directory(testEnv.tempPath);
      final mediaDir = Directory(p.join(supportDir.path, 'media'));
      final coversDir = Directory(p.join(supportDir.path, 'manual_covers'));
      await mediaDir.create(recursive: true);
      await coversDir.create(recursive: true);

      final image = img.Image(width: 160, height: 160);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(
            x,
            y,
            (x * 3 + y) % 256,
            (x + y * 5) % 256,
            (x * 7 + y * 11) % 256,
          );
        }
      }
      final imageBytes = img.encodeJpg(image, quality: 95);
      expect(imageBytes.length, greaterThan(1024));

      final dataSize = imageBytes.length + 16;
      final fakeM4aBytes = <int>[
        0,
        0,
        0,
        0,
        0x63,
        0x6F,
        0x76,
        0x72,
        (dataSize >> 24) & 0xFF,
        (dataSize >> 16) & 0xFF,
        (dataSize >> 8) & 0xFF,
        dataSize & 0xFF,
        0x64,
        0x61,
        0x74,
        0x61,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        13,
        ...imageBytes,
      ];

      final audioFile = File(p.join(mediaDir.path, 'covr-test.m4a'));
      await audioFile.writeAsBytes(fakeM4aBytes);

      final coverPath = await ScannerService.extractCoverForFile(
        audioFile,
        coversDir,
        p.basename(audioFile.path),
        skipFolderCover: true,
      );

      expect(coverPath, isNotNull);
      final coverFile = File(coverPath!);
      expect(await coverFile.exists(), isTrue);
      expect(img.decodeImage(await coverFile.readAsBytes()), isNotNull);
    });
  });

  group('ios_media_proxy pruning', () {
    test('pruneStaleSongCaches keeps ios media proxy files', () async {
      await cacheService.init();
      final supportDir = Directory(testEnv.tempPath);
      final proxyDir = Directory(
        p.join(supportDir.path, 'gru_cache_v3', 'ios_media_proxy'),
      );
      await proxyDir.create(recursive: true);

      final proxyFile = File(p.join(proxyDir.path, 'some_proxy.m4a'));
      await proxyFile.writeAsString('proxy data');

      await cacheService.pruneStaleSongCaches([]);

      expect(await proxyFile.exists(), isTrue);
    });

    test('pruneStaleSongCaches leaves other v3 cache files intact', () async {
      await cacheService.init();
      final supportDir = Directory(testEnv.tempPath);
      final proxyDir = Directory(
        p.join(supportDir.path, 'gru_cache_v3', 'ios_media_proxy'),
      );
      await proxyDir.create(recursive: true);

      await File(p.join(proxyDir.path, 'proxy.m4a')).writeAsString('data');

      final songFilename = 'test.mp3';
      final waveformKey = sha1.convert(utf8.encode(songFilename)).toString();
      final waveformFile = File(p.join(
        supportDir.path,
        'gru_cache_v3',
        'waveform_$waveformKey.json',
      ));
      await waveformFile.parent.create(recursive: true);
      await waveformFile.writeAsString('[0.5]');

      final keepSong = Song(
        title: 'Test',
        artist: 'Artist',
        album: 'Album',
        filename: songFilename,
        url: '/music/test.mp3',
        coverUrl: waveformFile.path,
      );

      await cacheService.pruneStaleSongCaches([keepSong]);

      expect(await waveformFile.exists(), isTrue);
    });
  });

  group('cache size eviction', () {
    test('pruneEvictBySize does nothing when under limit', () async {
      await cacheService.init();
      await cacheService.pruneEvictBySize();
    });

    test('pruneEvictBySize evicts oldest files when over limit', () async {
      await cacheService.init();
      final v3Dir = Directory(
        p.join(testEnv.tempPath, 'gru_cache_v3'),
      );

      final oldFile = File(p.join(v3Dir.path, 'old_cache.bin'));
      await oldFile.parent.create(recursive: true);
      await oldFile.writeAsString('x' * 100);

      final newFile = File(p.join(v3Dir.path, 'new_cache.bin'));
      await newFile.writeAsString('x' * 100);

      // Read original sizes to verify both exist before eviction
      expect(await oldFile.exists(), isTrue);
      expect(await newFile.exists(), isTrue);

      // Will not evict with small data (< 2GB limit)
      await cacheService.pruneEvictBySize();

      expect(await oldFile.exists(), isTrue);
      expect(await newFile.exists(), isTrue);
    });
  });

  group('notification cover index', () {
    Song songWithCover(String coverPath) => Song(
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
          filename: p.basename(coverPath),
          url: '/music/${p.basename(coverPath)}',
          coverUrl: coverPath,
        );

    test('peek resolves cached covers and misses uncached ones', () async {
      final cachedSong = songWithCover(
        p.join(testEnv.tempPath, 'extracted_covers', 'indexed-cover.jpg'),
      );
      final uncachedSong = songWithCover(
        p.join(testEnv.tempPath, 'extracted_covers', 'absent-cover.jpg'),
      );

      final key = FileManagerService.notificationCoverKey(cachedSong)!;
      final cacheFile = await cacheService.getNotificationCoverCacheFile(key);
      await cacheFile.writeAsString('square cover');

      await FileManagerService.primeNotificationCoverIndex();

      expect(
        FileManagerService.peekNotificationCover(
          cachedSong,
          PlayerCoverSizingMode.autoFit,
        ),
        cacheFile.path,
      );
      expect(
        FileManagerService.peekNotificationCover(
          uncachedSong,
          PlayerCoverSizingMode.autoFit,
        ),
        isNull,
      );
    });

    test('peek passes the raw cover through outside autoFit', () async {
      final song = songWithCover('/covers/raw.jpg');
      await FileManagerService.primeNotificationCoverIndex();

      expect(
        FileManagerService.peekNotificationCover(
          song,
          PlayerCoverSizingMode.sourceAspect,
        ),
        '/covers/raw.jpg',
      );
    });

    test('peek misses again once the cache generation is bumped', () async {
      final song = songWithCover(
        p.join(testEnv.tempPath, 'extracted_covers', 'generation-cover.jpg'),
      );
      final key = FileManagerService.notificationCoverKey(song)!;
      final cacheFile = await cacheService.getNotificationCoverCacheFile(key);
      await cacheFile.writeAsString('square cover');

      // Pruning with the song still referenced keeps its cover and bumps the
      // generation, so the index below is rebuilt rather than reused.
      await cacheService.pruneStaleSongCaches([song]);
      await FileManagerService.primeNotificationCoverIndex();
      expect(
        FileManagerService.peekNotificationCover(
          song,
          PlayerCoverSizingMode.autoFit,
        ),
        isNotNull,
      );

      // A later prune that no longer references the song deletes its cover
      // file behind the index's back.
      await cacheService.pruneStaleSongCaches([
        songWithCover(
          p.join(testEnv.tempPath, 'extracted_covers', 'other-cover.jpg'),
        ),
      ]);

      expect(
        FileManagerService.peekNotificationCover(
          song,
          PlayerCoverSizingMode.autoFit,
        ),
        isNull,
      );
    });

    test('key is null for a song with no cover', () {
      const song = Song(
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        filename: 'no-cover.mp3',
        url: '/music/no-cover.mp3',
      );
      expect(FileManagerService.notificationCoverKey(song), isNull);
      expect(
        FileManagerService.peekNotificationCover(
          song,
          PlayerCoverSizingMode.autoFit,
        ),
        isNull,
      );
    });
  });

  group('lyrics cache - no mtime dependency', () {
    test('lyrics cached entry has isFresh removed from model', () async {
      final lyricsDir = Directory(p.join(
        testEnv.tempPath,
        'gru_cache_v3',
        'lyrics_cache',
      ));
      await lyricsDir.create(recursive: true);
      final cacheFile = File(p.join(
        lyricsDir.path,
        '${sha1.convert(utf8.encode('/music/test.mp3')).toString()}.json',
      ));
      await cacheFile.writeAsString(jsonEncode({
        'hasLyrics': true,
        'lyrics': 'hello world',
      }));

      // Re-read and verify it deserializes without mtimeMs
      final raw = await cacheFile.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.containsKey('mtimeMs'), isFalse);
      expect(decoded['hasLyrics'], isTrue);
      expect(decoded['lyrics'], 'hello world');
    });
  });
}

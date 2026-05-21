import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:wispie/models/song.dart';
import 'package:wispie/services/cache_service.dart';
import 'package:wispie/services/color_extraction_service.dart';

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
    final keepMtime = (await keepAudio.lastModified()).millisecondsSinceEpoch;
    await keepLyrics.writeAsString(jsonEncode({
      'mtimeMs': keepMtime,
      'hasLyrics': true,
      'lyrics': 'lyrics',
    }));
    await dropLyrics.writeAsString(jsonEncode({
      'mtimeMs': (await dropAudio.lastModified()).millisecondsSinceEpoch,
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
}

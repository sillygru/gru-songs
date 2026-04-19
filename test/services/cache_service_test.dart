import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/services/cache_service.dart';

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
}

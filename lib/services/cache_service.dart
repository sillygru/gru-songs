import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CacheService {
  static const keyAudio = 'audio_cache';
  static const keyImages = 'image_cache';

  static final CacheManager audioCache = CacheManager(
    Config(
      keyAudio,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: keyAudio),
    ),
  );

  static final CacheManager imageCache = CacheManager(
    Config(
      keyImages,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 500,
      repo: JsonCacheInfoRepository(databaseName: keyImages),
    ),
  );
}

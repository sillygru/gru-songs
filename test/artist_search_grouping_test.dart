import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/data/repositories/search_index_repository.dart';
import 'package:wispie/domain/models/search_filter.dart';
import 'package:wispie/domain/services/search_service.dart';
import 'package:wispie/models/song.dart';
import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() async {
    await testEnv.tearDown();
  });

  test(
      'rebuildIndex updates database entries when metadata changes even if mtime is unchanged',
      () async {
    final searchIndexRepo = SearchIndexRepository();
    await searchIndexRepo.init();

    // Fast scan song placeholder
    const fastSong = Song(
      title: 'test_song.mp3',
      artist: 'Unknown Artist',
      album: 'Unknown Album',
      filename: 'test_song.mp3',
      url: '/music/test_song.mp3',
      mtime: 1700000000.0,
    );

    await searchIndexRepo.rebuildIndex([fastSong]);

    final initialMatches = await searchIndexRepo.search(
      query: 'BoyWithUke',
      searchTitles: true,
      searchArtists: true,
      searchAlbums: true,
      searchLyrics: false,
    );
    expect(initialMatches, isEmpty);

    // Enriched song with same mtime
    const enrichedSong = Song(
      title: 'Toxic',
      artist: 'BoyWithUke',
      album: 'Serotonin Dreams',
      filename: 'test_song.mp3',
      url: '/music/test_song.mp3',
      mtime: 1700000000.0,
    );

    await searchIndexRepo.rebuildIndex([enrichedSong]);

    final enrichedMatches = await searchIndexRepo.search(
      query: 'BoyWithUke',
      searchTitles: true,
      searchArtists: true,
      searchAlbums: true,
      searchLyrics: false,
    );
    expect(enrichedMatches.length, equals(1));
    expect(enrichedMatches.first.filename, equals('test_song.mp3'));
  });

  test('SearchService returns matches for multi-song artist', () async {
    final searchService = SearchService();
    await searchService.init();

    const song1 = Song(
      title: 'BoyWithUke - Toxic',
      artist: 'BoyWithUke',
      album: 'Serotonin Dreams',
      filename: 'toxic.mp3',
      url: '/music/toxic.mp3',
    );
    const song2 = Song(
      title: 'Understand',
      artist: 'BoyWithUke',
      album: 'Serotonin Dreams',
      filename: 'understand.mp3',
      url: '/music/understand.mp3',
    );

    await searchService.rebuildIndex([song1, song2]);

    final results = await searchService.search(
      query: 'BoyWithUke',
      filterState: const SearchFilterState(all: true),
      allSongs: [song1, song2],
    );

    expect(results.length, equals(2));
  });
}

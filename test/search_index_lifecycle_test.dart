import 'package:flutter_test/flutter_test.dart';
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
      'SearchService continues working after updating metadata or disposing temporary service',
      () async {
    final mainSearchService = SearchService();
    await mainSearchService.init();

    const initialSong = Song(
      title: 'Original Title',
      artist: 'Original Artist',
      album: 'Original Album',
      filename: 'test_song.mp3',
      url: '/music/test_song.mp3',
      duration: Duration(seconds: 180),
    );

    await mainSearchService.rebuildIndex([initialSong]);

    final initialResults = await mainSearchService.search(
      query: 'Original',
      filterState: const SearchFilterState(all: true),
      allSongs: [initialSong],
    );
    expect(initialResults.length, equals(1));
    expect(initialResults.first.song.title, equals('Original Title'));

    // Simulate metadata edit via temporary SearchService
    final tempSearchService = SearchService();
    await tempSearchService.init();

    const updatedSong = Song(
      title: 'Updated Title',
      artist: 'Updated Artist',
      album: 'Updated Album',
      filename: 'test_song.mp3',
      url: '/music/test_song.mp3',
      duration: Duration(seconds: 180),
    );

    await tempSearchService.updateSong(updatedSong);
    await tempSearchService.dispose();

    // Verify main search service still functions without throwing closed db error
    final updatedResults = await mainSearchService.search(
      query: 'Updated',
      filterState: const SearchFilterState(all: true),
      allSongs: [updatedSong],
    );

    expect(updatedResults.length, equals(1));
    expect(updatedResults.first.song.title, equals('Updated Title'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wispie/services/passive_art_fetcher_service.dart';
import 'test_helpers.dart';

void main() {
  late TestEnvironment testEnv;

  setUpAll(() async {
    testEnv = TestEnvironment();
    testEnv.setUp();
  });

  tearDownAll(() async {
    testEnv.tearDown();
  });

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('art_fetch_attempted_artists');
    await prefs.remove('art_fetch_attempted_albums');
    await PassiveArtFetcherService.instance.clearAttempted();
  });

  test('clearAttempted removes previously persisted misses', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('art_fetch_attempted_artists', ['radiohead']);
    await prefs
        .setStringList('art_fetch_attempted_albums', ['radiohead|ok computer']);

    await PassiveArtFetcherService.instance.clearAttempted();

    final artists = prefs.getStringList('art_fetch_attempted_artists');
    final albums = prefs.getStringList('art_fetch_attempted_albums');
    expect(artists, isNull);
    expect(albums, isNull);
  });

  test('forgetArtistAttempt persists the removal of a previous miss', () async {
    final prefs = await SharedPreferences.getInstance();
    // A miss recorded by an earlier session.
    await prefs.setStringList('art_fetch_attempted_artists', ['radiohead']);

    PassiveArtFetcherService.instance.forgetArtistAttempt('Radiohead');

    // Debounced persist writes after ~3s.
    await Future<void>.delayed(const Duration(seconds: 4));
    final artists = prefs.getStringList('art_fetch_attempted_artists') ?? [];
    expect(artists, isNot(contains('radiohead')));
  });
  test('forgetAlbumAttempt persists the removal of a previous miss', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs
        .setStringList('art_fetch_attempted_albums', ['radiohead|ok computer']);

    PassiveArtFetcherService.instance
        .forgetAlbumAttempt('Ok Computer', 'Radiohead');

    await Future<void>.delayed(const Duration(seconds: 4));
    final albums = prefs.getStringList('art_fetch_attempted_albums') ?? [];
    expect(albums, isNot(contains('radiohead|ok computer')));
  });

  test('session-only marks never leak into persisted state', () async {
    final prefs = await SharedPreferences.getInstance();

    // set/remove mark attempts in memory only; a flush must not persist them.
    PassiveArtFetcherService.instance.markArtistAttempted('Radiohead');
    PassiveArtFetcherService.instance.markAlbumAttempted('Ok Computer', null);

    await Future<void>.delayed(const Duration(seconds: 4));
    final artists = prefs.getStringList('art_fetch_attempted_artists') ?? [];
    final albums = prefs.getStringList('art_fetch_attempted_albums') ?? [];
    expect(artists, isNot(contains('radiohead')));
    expect(albums, isNot(contains('ok computer')));
  });
}

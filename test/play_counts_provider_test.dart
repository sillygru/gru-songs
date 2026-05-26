import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/models/song.dart';
import 'package:wispie/providers/providers.dart';

List<Song> _testSongs = [];

class _FakeSongsNotifier extends SongsNotifier {
  @override
  Future<List<Song>> build() async => _testSongs;
}

void main() {
  test('playCountsProvider mirrors the latest songs state', () async {
    _testSongs = [
      const Song(
        title: 'One',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/one.mp3',
        url: '/music/one.mp3',
        playCount: 2,
      ),
      const Song(
        title: 'Two',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/two.mp3',
        url: '/music/two.mp3',
        playCount: 5,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        songsProvider.overrideWith(_FakeSongsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(songsProvider.future);
    final initialCounts = container.read(playCountsProvider);
    expect(initialCounts['/music/one.mp3'], 2);
    expect(initialCounts['/music/two.mp3'], 5);

    _testSongs = [
      const Song(
        title: 'One',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/one.mp3',
        url: '/music/one.mp3',
        playCount: 7,
      ),
      const Song(
        title: 'Two',
        artist: 'Artist',
        album: 'Album',
        filename: '/music/two.mp3',
        url: '/music/two.mp3',
        playCount: 9,
      ),
    ];

    container.invalidate(songsProvider);
    await container.read(songsProvider.future);

    final refreshedCounts = container.read(playCountsProvider);
    expect(refreshedCounts['/music/one.mp3'], 7);
    expect(refreshedCounts['/music/two.mp3'], 9);
  });
}

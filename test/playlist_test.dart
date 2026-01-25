import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/playlist.dart';
import 'package:gru_songs/providers/user_data_provider.dart';

void main() {
  group('Playlist Model', () {
    test('Playlist.fromJson and toJson should be consistent', () {
      final json = {
        'id': 'pl1',
        'name': 'Test Playlist',
        'created_at': 1000.0,
        'updated_at': 1100.0,
        'songs': [
          {'song_filename': 's1.mp3', 'added_at': 1050.0}
        ]
      };

      final playlist = Playlist.fromJson(json);
      expect(playlist.id, 'pl1');
      expect(playlist.name, 'Test Playlist');
      expect(playlist.songs.length, 1);
      expect(playlist.songs[0].songFilename, 's1.mp3');

      final backToJson = playlist.toJson();
      expect(backToJson['id'], 'pl1');
      expect(backToJson['name'], 'Test Playlist');
      expect(backToJson['songs'][0]['song_filename'], 's1.mp3');
    });
  });

  group('UserDataState with Playlists', () {
    test('copyWith should update playlists', () {
      final state = UserDataState();
      final playlist = Playlist(
        id: '1',
        name: 'My PL',
        createdAt: 0,
        updatedAt: 0,
        songs: [],
      );

      final newState = state.copyWith(playlists: [playlist]);
      expect(newState.playlists.length, 1);
      expect(newState.playlists[0].name, 'My PL');
    });
  });
}

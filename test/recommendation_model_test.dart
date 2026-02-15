import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/playlist.dart';

void main() {
  group('Playlist Model - Recommendation Support', () {
    test('Playlist.fromJson should handle recommendation fields', () {
      final json = {
        'id': 'top_hits',
        'name': 'My Top Hits',
        'description': 'Frozen description',
        'is_recommendation': 1,
        'created_at': 1000.0,
        'updated_at': 1100.0,
        'songs': [
          {'song_filename': 's1.mp3', 'added_at': 1050.0}
        ]
      };

      final playlist = Playlist.fromJson(json);
      expect(playlist.id, 'top_hits');
      expect(playlist.name, 'My Top Hits');
      expect(playlist.description, 'Frozen description');
      expect(playlist.isRecommendation, true);
      expect(playlist.songs.length, 1);
    });

    test('Playlist.toJson should include recommendation fields', () {
      final playlist = Playlist(
        id: 'fresh_finds',
        name: 'New Tracks',
        description: 'Newly added',
        isRecommendation: true,
        createdAt: 2000.0,
        updatedAt: 2100.0,
        songs: [],
      );

      final json = playlist.toJson();
      expect(json['id'], 'fresh_finds');
      expect(json['description'], 'Newly added');
      expect(json['is_recommendation'], 1);
    });

    test('Playlist.copyWith should update recommendation fields', () {
      final playlist = Playlist(
        id: '1',
        name: 'PL',
        createdAt: 0,
        updatedAt: 0,
        songs: [],
      );

      final updated = playlist.copyWith(
        isRecommendation: true,
        description: 'New Desc',
      );

      expect(updated.isRecommendation, true);
      expect(updated.description, 'New Desc');
    });
  });
}

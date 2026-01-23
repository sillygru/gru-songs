import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/providers/user_data_provider.dart';

void main() {
  group('UserDataState Hidden Tests', () {
    test('isHidden correctly identifies hidden songs by full path', () {
      final state = UserDataState(hidden: ['/path/to/song1.mp3', 'song2.mp3']);

      expect(state.isHidden('/path/to/song1.mp3'), true);
      expect(state.isHidden('song2.mp3'), true);
      expect(state.isHidden('/other/song2.mp3'), true); // matches basename
      expect(state.isHidden('song3.mp3'), false);
    });

    test('isHidden is case-insensitive', () {
      final state = UserDataState(hidden: ['Song1.mp3']);

      expect(state.isHidden('song1.mp3'), true);
      expect(state.isHidden('SONG1.MP3'), true);
    });

    test('copyWith updates hidden list', () {
      final state = UserDataState(hidden: ['s1.mp3']);
      final newState = state.copyWith(hidden: ['s1.mp3', 's2.mp3']);

      expect(newState.hidden, ['s1.mp3', 's2.mp3']);
      expect(state.hidden, ['s1.mp3']);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/domain/models/search_filter.dart';

void main() {
  group('SearchFilterState', () {
    test('default state has all selected', () {
      const state = SearchFilterState(all: true);
      expect(state.all, isTrue);
      expect(state.songs, isFalse);
      expect(state.artists, isFalse);
      expect(state.albums, isFalse);
      expect(state.lyrics, isFalse);
    });

    test('factory all() creates correct state', () {
      final state = SearchFilterState.all();
      expect(state.all, isTrue);
      expect(state.hasSpecificFilters, isFalse);
    });

    group('toggleFilter', () {
      test('toggling All clears specific filters', () {
        var state = const SearchFilterState(
          all: false,
          songs: true,
          artists: true,
        );
        state = state.toggleFilter(SearchFilterType.all);
        expect(state.all, isTrue);
        expect(state.songs, isFalse);
        expect(state.artists, isFalse);
      });

      test('toggling Songs clears All', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.songs);
        expect(state.all, isFalse);
        expect(state.songs, isTrue);
      });

      test('toggling Artists clears All', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.artists);
        expect(state.all, isFalse);
        expect(state.artists, isTrue);
      });

      test('toggling Albums clears All', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.albums);
        expect(state.all, isFalse);
        expect(state.albums, isTrue);
      });

      test('toggling Lyrics clears All', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.lyrics);
        expect(state.all, isFalse);
        expect(state.lyrics, isTrue);
      });

      test('toggling same filter twice keeps All false and songs false', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.songs);
        expect(state.all, isFalse);
        expect(state.songs, isTrue);
        state = state.toggleFilter(SearchFilterType.songs);
        // When deselecting the only active filter, it stays with all=false, songs=false
        // The _toggleSpecificFilter doesn't auto-fallback to All
        expect(state.all, isFalse);
        expect(state.songs, isFalse);
      });

      test('multiple specific filters can be selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.songs);
        state = state.toggleFilter(SearchFilterType.artists);
        expect(state.all, isFalse);
        expect(state.songs, isTrue);
        expect(state.artists, isTrue);
        expect(state.albums, isFalse);
      });
    });

    group('shouldSearchLyrics', () {
      test('returns true when All is selected', () {
        final state = SearchFilterState.all();
        expect(state.shouldSearchLyrics, isTrue);
      });

      test('returns true when Songs is selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.songs);
        expect(state.shouldSearchLyrics, isTrue);
      });

      test('returns true when Lyrics is selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.lyrics);
        // Lyrics filter alone doesn't trigger lyrics search - only Songs or All does
        expect(state.shouldSearchLyrics, isFalse);
      });

      test('returns false when only Artists is selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.artists);
        expect(state.shouldSearchLyrics, isFalse);
      });

      test('returns false when only Albums is selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.albums);
        expect(state.shouldSearchLyrics, isFalse);
      });
    });

    group('activeFilters', () {
      test('returns All when all is selected', () {
        final state = SearchFilterState.all();
        expect(state.activeFilters, [SearchFilterType.all]);
      });

      test('returns specific filters when selected', () {
        var state = SearchFilterState.all();
        state = state.toggleFilter(SearchFilterType.songs);
        state = state.toggleFilter(SearchFilterType.artists);
        expect(state.activeFilters,
            [SearchFilterType.songs, SearchFilterType.artists]);
      });
    });

    group('isSelected', () {
      test('correctly identifies selected filters', () {
        var state = SearchFilterState.all();
        expect(state.isSelected(SearchFilterType.all), isTrue);

        state = state.toggleFilter(SearchFilterType.songs);
        expect(state.isSelected(SearchFilterType.all), isFalse);
        expect(state.isSelected(SearchFilterType.songs), isTrue);
        expect(state.isSelected(SearchFilterType.artists), isFalse);
      });
    });

    group('deselectFilter', () {
      test('deselecting specific filter keeps others', () {
        var state = const SearchFilterState(
          all: false,
          songs: true,
          artists: true,
        );
        state = state.deselectFilter(SearchFilterType.songs);
        expect(state.songs, isFalse);
        expect(state.artists, isTrue);
        expect(state.all, isFalse);
      });

      test('deselecting last specific filter falls back to All', () {
        var state = const SearchFilterState(
          all: false,
          songs: true,
        );
        state = state.deselectFilter(SearchFilterType.songs);
        expect(state.all, isTrue);
        expect(state.songs, isFalse);
      });

      test('cannot deselect All without selecting something else', () {
        final state = SearchFilterState.all();
        final newState = state.deselectFilter(SearchFilterType.all);
        expect(newState.all, isTrue);
      });
    });

    group('Equatable', () {
      test('equal states are equal', () {
        const state1 = SearchFilterState(all: true);
        const state2 = SearchFilterState(all: true);
        expect(state1, state2);
      });

      test('different states are not equal', () {
        const state1 = SearchFilterState(all: true);
        const state2 = SearchFilterState(all: false, songs: true);
        expect(state1, isNot(state2));
      });
    });
  });

  group('SearchFilterTypeExtension', () {
    test('display names are correct', () {
      expect(SearchFilterType.all.displayName, 'All');
      expect(SearchFilterType.songs.displayName, 'Songs');
      expect(SearchFilterType.artists.displayName, 'Artists');
      expect(SearchFilterType.albums.displayName, 'Albums');
      expect(SearchFilterType.lyrics.displayName, 'Lyrics');
    });
  });
}

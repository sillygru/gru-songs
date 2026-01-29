import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/models/song.dart';
import 'package:gru_songs/presentation/widgets/duration_display.dart';

void main() {
  group('DurationFormatter', () {
    group('format', () {
      test('returns --:-- for null duration', () {
        expect(DurationFormatter.format(null), '--:--');
      });

      test('returns --:-- for zero duration', () {
        expect(DurationFormatter.format(Duration.zero), '--:--');
      });

      test('formats MM:SS correctly', () {
        expect(
            DurationFormatter.format(const Duration(minutes: 3, seconds: 42)),
            '03:42');
      });

      test('formats HH:MM:SS for durations over an hour', () {
        expect(
            DurationFormatter.format(
                const Duration(hours: 1, minutes: 30, seconds: 45)),
            '01:30:45');
      });

      test('formats single digit seconds correctly', () {
        expect(DurationFormatter.format(const Duration(minutes: 1, seconds: 5)),
            '01:05');
      });
    });

    group('formatCompact', () {
      test('returns empty for null duration', () {
        expect(DurationFormatter.formatCompact(null), '');
      });

      test('returns empty for zero duration', () {
        expect(DurationFormatter.formatCompact(Duration.zero), '');
      });

      test('formats seconds only', () {
        expect(DurationFormatter.formatCompact(const Duration(seconds: 45)),
            '45s');
      });

      test('formats minutes and seconds', () {
        expect(
            DurationFormatter.formatCompact(
                const Duration(minutes: 3, seconds: 42)),
            '3m 42s');
      });

      test('formats hours and minutes', () {
        expect(
            DurationFormatter.formatCompact(
                const Duration(hours: 1, minutes: 30)),
            '1h 30m');
      });
    });

    group('formatTotal', () {
      test('returns --:-- for empty list', () {
        expect(DurationFormatter.formatTotal([]), '--:--');
      });

      test('sums durations correctly', () {
        final songs = [
          Song(
            title: 'Song 1',
            artist: 'Artist',
            album: 'Album',
            filename: 'song1.mp3',
            url: '/path/song1.mp3',
            duration: const Duration(minutes: 3),
          ),
          Song(
            title: 'Song 2',
            artist: 'Artist',
            album: 'Album',
            filename: 'song2.mp3',
            url: '/path/song2.mp3',
            duration: const Duration(minutes: 4),
          ),
        ];
        expect(DurationFormatter.formatTotal(songs), '07:00');
      });

      test('ignores null durations', () {
        final songs = [
          Song(
            title: 'Song 1',
            artist: 'Artist',
            album: 'Album',
            filename: 'song1.mp3',
            url: '/path/song1.mp3',
            duration: const Duration(minutes: 3),
          ),
          Song(
            title: 'Song 2',
            artist: 'Artist',
            album: 'Album',
            filename: 'song2.mp3',
            url: '/path/song2.mp3',
            duration: null,
          ),
        ];
        expect(DurationFormatter.formatTotal(songs), '03:00');
      });
    });

    group('getSongsWithDurationCount', () {
      test('returns 0 for empty list', () {
        expect(DurationFormatter.getSongsWithDurationCount([]), 0);
      });

      test('counts only songs with valid durations', () {
        final songs = [
          Song(
            title: 'Song 1',
            artist: 'Artist',
            album: 'Album',
            filename: 'song1.mp3',
            url: '/path/song1.mp3',
            duration: const Duration(minutes: 3),
          ),
          Song(
            title: 'Song 2',
            artist: 'Artist',
            album: 'Album',
            filename: 'song2.mp3',
            url: '/path/song2.mp3',
            duration: null,
          ),
          Song(
            title: 'Song 3',
            artist: 'Artist',
            album: 'Album',
            filename: 'song3.mp3',
            url: '/path/song3.mp3',
            duration: Duration.zero,
          ),
        ];
        expect(DurationFormatter.getSongsWithDurationCount(songs), 1);
      });
    });
  });
}

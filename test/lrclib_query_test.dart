import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/lrclib_query.dart';

void main() {
  group('cleanSearchTitle', () {
    test('strips a descriptor suffix and a matching artist prefix', () {
      // The real "Pretty Lies.m4a" case: YouTube-ripped tags.
      expect(
        cleanSearchTitle('Yoza - Pretty Lies (Official Audio)', artist: 'Yoza'),
        'Pretty Lies',
      );
      expect(
        cleanSearchTitle('Yoza - Pretty Lies [Official Music Video]',
            artist: 'Yoza'),
        'Pretty Lies',
      );
    });

    test('strips descriptor brackets without an artist prefix', () {
      expect(cleanSearchTitle('Pretty Lies (Official Audio)', artist: 'Yoza'),
          'Pretty Lies');
      expect(cleanSearchTitle('Song (Lyrics)', artist: 'A'), 'Song');
      expect(cleanSearchTitle('Song [HD]'), 'Song');
    });

    test('leaves a clean title untouched', () {
      expect(cleanSearchTitle('Pretty Lies', artist: 'Yoza'), 'Pretty Lies');
    });

    test('keeps meaningful brackets that pick out a recording', () {
      expect(cleanSearchTitle('Some Song (Remix)', artist: 'A'),
          'Some Song (Remix)');
      expect(cleanSearchTitle('Some Song (Acoustic)'), 'Some Song (Acoustic)');
    });

    test('only strips the prefix when it matches the artist tag', () {
      // "Title - Subtitle" must survive when the prefix is not the artist.
      expect(cleanSearchTitle('Title - Subtitle', artist: 'Yoza'),
          'Title - Subtitle');
      // Prefix match ignores case and punctuation.
      expect(cleanSearchTitle('YOZA - Pretty Lies', artist: 'Yoza'),
          'Pretty Lies');
    });

    test('falls back to the original when cleaning empties the title', () {
      expect(cleanSearchTitle('(Official Audio)', artist: 'Yoza'),
          '(Official Audio)');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/rich_lyrics.dart';
import 'package:wispie/models/song.dart';

void main() {
  test('parses the compact music-utils richSync payload', () {
    final rich = RichLyrics.fromApi({
      'format': 'json',
      'syncType': 'richsync',
      'content': {
        'title': 'Example',
        'artist': 'Artist',
        'duration': 20.5,
        'lines': [
          [
            1.25,
            4.5,
            'Hello, world',
            [
              [1.25, 2.0, 'Hello,'],
              [2.2, 4.5, 'world'],
            ],
          ],
        ],
      },
    });

    expect(rich.lines, hasLength(1));
    expect(rich.lines.single.start, const Duration(milliseconds: 1250));
    expect(rich.lines.single.words, hasLength(2));
    expect(rich.lines.single.words.last.text, 'world');
    expect(rich.toLrc(), '[00:01.25]Hello, world');
  });

  test('creates word timings for line-synced lyrics and pauses at commas', () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 0),
        text: 'One, two three',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 6),
        text: 'Next line',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final words = rich.lines.first.words;

    expect(words, hasLength(3));
    expect(words[1].start - words[0].start,
        greaterThan(words[2].start - words[1].start));
    expect(words.first.start, Duration.zero);
    expect(words.last.end, const Duration(seconds: 6));
  });
}

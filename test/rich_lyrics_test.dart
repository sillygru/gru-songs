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

  test('merges syllable timings back into source words', () {
    final rich = RichLyrics.fromApi(const {
      'content': {
        'lines': [
          [
            7.184,
            13.436,
            "I've been so busy, ignoring, and hiding",
            [
              [7.184, 7.532, "I've"],
              [7.532, 7.819, 'been'],
              [7.819, 8.112, 'so'],
              [8.112, 9.42, 'busy,'],
              [9.832, 10.157, 'ig'],
              [10.157, 10.801, 'nor'],
              [10.801, 11.285, 'ing,'],
              [11.846, 12.146, 'and'],
              [12.146, 12.865, 'hid'],
              [12.865, 13.436, 'ing'],
            ],
          ],
        ],
      },
    });

    final words = rich.lines.single.words;
    expect(words.map((word) => word.text), [
      "I've",
      'been',
      'so',
      'busy,',
      'ignoring,',
      'and',
      'hiding',
    ]);
    expect(words[4].start, const Duration(milliseconds: 9832));
    expect(words[4].end, const Duration(milliseconds: 11285));
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

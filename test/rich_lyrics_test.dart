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
    expect(rich.lines.single.isSimulated, isFalse);
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

  test('creates natural character-weighted word timings for line-synced lyrics',
      () {
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
    final line = rich.lines.first;
    final words = line.words;

    expect(line.isSimulated, isTrue);
    expect(words, hasLength(3));
    expect(words.map((w) => w.text), ['One,', 'two', 'three']);
    expect(words.first.start, Duration.zero);
    expect(words[1].start, greaterThan(words[0].start));
    expect(words[2].start, greaterThan(words[1].start));
    expect(words.every((w) => w.duration > Duration.zero), isTrue);
    expect(words.last.end, lessThanOrEqualTo(line.end));
    expect(line.end, const Duration(seconds: 6));
  });

  test(
      'caps vocal duration in long intervals (e.g. 20s gap) to prevent slow motion',
      () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 10),
        text: 'Yeah let us go',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 30),
        text: 'After guitar solo',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final firstLine = rich.lines.first;

    // Line window is 20s (10s to 30s)
    expect(firstLine.end, const Duration(seconds: 30));
    // The vocal singing duration for 4 short words must finish in under 3.5s
    final lastWordEnd = firstLine.words.last.end;
    expect(
      lastWordEnd - firstLine.start,
      lessThan(const Duration(milliseconds: 3500)),
    );
    expect(
      lastWordEnd - firstLine.start,
      greaterThan(const Duration(milliseconds: 800)),
    );
  });

  test('allocates more time to multi-syllable words than single-syllable words',
      () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 0),
        text: 'a extraordinarily big',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 4),
        text: 'next',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final words = rich.lines.first.words;

    final shortWordDuration = words[0].duration;
    final longWordDuration = words[1].duration;

    expect(longWordDuration, greaterThan(shortWordDuration * 2));
  });

  test('adapts pacing based on estimated song cadence', () {
    const fastRapSong = [
      LyricLine(
          time: Duration(seconds: 0),
          text: 'I am running very fast on the track',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 1500),
          text: 'Spitting every rhyme that you ever heard',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 3000),
          text: 'Never gonna stop till the beat is done',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 4500),
          text: 'Short break line',
          isSynced: true),
      LyricLine(
          time: Duration(seconds: 10), text: 'Back in action', isSynced: true),
    ];

    const slowBallad = [
      LyricLine(time: Duration(seconds: 0), text: 'Stay', isSynced: true),
      LyricLine(time: Duration(seconds: 4), text: 'With me', isSynced: true),
      LyricLine(time: Duration(seconds: 8), text: 'Tonight', isSynced: true),
      LyricLine(time: Duration(seconds: 12), text: 'Forever', isSynced: true),
    ];

    final fastRich = RichLyrics.fromLyricLines(fastRapSong);
    final slowRich = RichLyrics.fromLyricLines(slowBallad);

    // Fast song's break line should have faster per-character pace than slow ballad words
    final fastBreakWords = fastRich.lines[3].words;
    final fastTotalVocal = fastBreakWords.last.end - fastBreakWords.first.start;

    expect(fastTotalVocal, lessThan(const Duration(milliseconds: 2200)));
    expect(slowRich.lines.first.words.first.duration,
        greaterThan(const Duration(milliseconds: 400)));
  });

  test('supports CJK character syllable counting', () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 0),
        text: '你好 世界',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 5),
        text: '再见',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final words = rich.lines.first.words;

    expect(words, hasLength(2));
    expect(words[0].text, '你好');
    expect(words[1].text, '世界');
    expect(words.last.end - words.first.start,
        lessThan(const Duration(milliseconds: 2500)));
  });

  test('inserts natural micro-pauses after punctuation marks', () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 0),
        text: 'Wait, listen to me.',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 5),
        text: 'Next line',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final words = rich.lines.first.words;

    expect(words, hasLength(4));
    // Word 1 ends before Word 2 starts because of trailing comma
    expect(words[1].start, greaterThan(words[0].end));
  });
}

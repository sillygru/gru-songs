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

    // Line window is 20s (10s to 30s) — ultra_fast uses silence-ratio vocal span, not elastic cap
    expect(firstLine.end, const Duration(seconds: 30));
    final lastWordEnd = firstLine.words.last.end;
    expect(
      lastWordEnd - firstLine.start,
      greaterThan(const Duration(milliseconds: 800)),
    );
    expect(
      lastWordEnd - firstLine.start,
      lessThanOrEqualTo(const Duration(milliseconds: 20000)),
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

    // ultra_fast 75th percentile + silence ratio gives ~5.5s vocal for 5.5s window
    expect(fastTotalVocal, lessThan(const Duration(milliseconds: 6000)));
    expect(fastTotalVocal, greaterThan(const Duration(milliseconds: 800)));
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
        lessThan(const Duration(milliseconds: 5500)));
    expect(words.last.end - words.first.start,
        greaterThan(const Duration(milliseconds: 800)));
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
    // ultra_fast uses contiguous boundaries with cadence pause offset, not explicit gaps
    final pause = words[1].start - words[0].end;
    expect(pause, greaterThanOrEqualTo(Duration.zero));
    // comma word should still be bounded and have non-zero duration
    expect(words[0].duration, greaterThan(Duration.zero));
    expect(words[1].duration, greaterThan(Duration.zero));
  });

  test(
      'sustains slow melismatic chorus phrases across measure (e.g. golden hour)',
      () {
    const goldenHourSnippet = [
      LyricLine(
          time: Duration(seconds: 17),
          text: 'It was just two lovers',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 18500),
          text:
              "Sittin' in the car, listening to Blonde, fallin' for each other",
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 22800),
          text:
              "Pink and orange skies, feelin' super childish, no Donald Glover",
          isSynced: true),
      LyricLine(
          time: Duration(seconds: 48),
          text: "It's your golden hour",
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 60800),
          text: 'You slow down time',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 67300),
          text: 'In your golden hour',
          isSynced: true),
    ];

    final rich = RichLyrics.fromLyricLines(goldenHourSnippet);
    // Line at index 4 is "You slow down time" (60.8s to 67.3s = 6.5s interval)
    final slowLine = rich.lines[4];
    final vocalSpan = slowLine.words.last.end - slowLine.words.first.start;

    // Must sustain across the measure (>= 5.0s) rather than rushing in 1-2 seconds
    expect(vocalSpan, greaterThan(const Duration(milliseconds: 5000)));
    expect(vocalSpan, lessThanOrEqualTo(const Duration(milliseconds: 7000)));

    // Function pickup word 'You' remains crisp (< 800ms with 0.35 damping) while content words absorb the stretch
    expect(slowLine.words[0].duration,
        lessThan(const Duration(milliseconds: 800)));
    expect(slowLine.words[1].duration,
        greaterThan(const Duration(milliseconds: 1200)));
    expect(slowLine.words[2].duration,
        greaterThan(const Duration(milliseconds: 1200)));
    expect(slowLine.words[3].duration,
        greaterThan(const Duration(milliseconds: 2000)));
  });

  test(
      'delivers fast rap lines with inter-line pauses briskly without dragging',
      () {
    const rapSnippet = [
      LyricLine(
          time: Duration(seconds: 0),
          text: 'I got money in my pocket and I run the game',
          isSynced: true),
      LyricLine(
          time: Duration(seconds: 4),
          text: 'Spitting fire every second you can know my name',
          isSynced: true),
      LyricLine(time: Duration(seconds: 8), text: 'Short line', isSynced: true),
      LyricLine(time: Duration(seconds: 12), text: 'Done', isSynced: true),
    ];

    final rich = RichLyrics.fromLyricLines(rapSnippet);
    final rapLine = rich.lines[0];
    final vocalSpan = rapLine.words.last.end - rapLine.words.first.start;

    // ultra_fast vocalSpan ~ lineDur - silenceRatio, ~4.0s window => ~3.9s
    expect(vocalSpan, lessThan(const Duration(milliseconds: 4100)));
    expect(vocalSpan, greaterThan(const Duration(milliseconds: 2000)));
  });

  test(
      'sustains standalone single-word climax lines across measure (e.g. Shine in golden hour)',
      () {
    const shineSnippet = [
      LyricLine(
          time: Duration(seconds: 0),
          text: 'I don’t need no light to see you',
          isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 4400), text: 'Shine', isSynced: true),
      LyricLine(
          time: Duration(milliseconds: 8100),
          text: "It's your golden hour",
          isSynced: true),
    ];

    final rich = RichLyrics.fromLyricLines(shineSnippet);
    // Line at index 1 is "Shine" (4.4s to 8.1s = 3.7s interval)
    final shineLine = rich.lines[1];
    final vocalSpan = shineLine.words.last.end - shineLine.words.first.start;

    // Single-word climax line must sustain across the measure (>= 3.2s)
    expect(vocalSpan, greaterThan(const Duration(milliseconds: 3200)));
    expect(vocalSpan, lessThanOrEqualTo(const Duration(milliseconds: 3700)));
  });

  test('sustains slow ballad lines with legato phrasing', () {
    const slowBalladSnippet = [
      LyricLine(
          time: Duration(seconds: 0),
          text: 'I will always love you',
          isSynced: true),
      LyricLine(
          time: Duration(seconds: 5),
          text: 'Will always love you',
          isSynced: true),
      LyricLine(
          time: Duration(seconds: 10), text: 'My darling you', isSynced: true),
      LyricLine(time: Duration(seconds: 15), text: 'End', isSynced: true),
    ];

    final rich = RichLyrics.fromLyricLines(slowBalladSnippet);
    final firstLine = rich.lines.first;
    final vocalSpan = firstLine.words.last.end - firstLine.words.first.start;

    // In a slow ballad (5s interval), singing should occupy >= 4.3s
    expect(vocalSpan, greaterThan(const Duration(milliseconds: 4300)));
  });

  test('splits compound hyphenated words into distinct timed sub-words', () {
    const lines = [
      LyricLine(
        time: Duration(seconds: 0),
        text: 'I am twenty-one years old',
        isSynced: true,
      ),
      LyricLine(
        time: Duration(seconds: 4),
        text: 'End',
        isSynced: true,
      ),
    ];

    final rich = RichLyrics.fromLyricLines(lines);
    final words = rich.lines.first.words;

    // "twenty-one" should be split into "twenty-" and "one"
    expect(words, hasLength(6));
    expect(words.map((w) => w.text).toList(), [
      'I',
      'am',
      'twenty-',
      'one',
      'years',
      'old',
    ]);
    expect(words[2].text, 'twenty-');
    expect(words[3].text, 'one');
    expect(words[3].start, greaterThanOrEqualTo(words[2].start));
    expect(words[3].end, greaterThan(words[2].end));
  });
}

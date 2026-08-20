import '../../models/song.dart';

/// One word or syllable segment in a rich-synchronized lyric line.
class RichLyricWord {
  final Duration start;
  final Duration end;
  final String text;

  const RichLyricWord({
    required this.start,
    required this.end,
    required this.text,
  });

  Duration get duration => end - start;
}

/// A lyric line with optional word-level timing.
class RichLyricLine {
  final Duration start;
  final Duration end;
  final String text;
  final List<RichLyricWord> words;
  final bool isSimulated;

  const RichLyricLine({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
    this.isSimulated = false,
  });
}

/// Compact rich-sync payload returned by music-utils.
///
/// The API deliberately uses tuples to keep the response small. This model
/// keeps the tuple parsing at the service boundary and gives the renderer a
/// null-safe shape that also works for locally generated word timings.
class RichLyrics {
  final String? title;
  final String? artist;
  final Duration? duration;
  final List<RichLyricLine> lines;

  const RichLyrics({
    this.title,
    this.artist,
    this.duration,
    required this.lines,
  });

  factory RichLyrics.fromApi(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const RichLyrics(lines: []);
    }

    final content = value['content'];
    if (content is! Map<String, dynamic>) {
      return const RichLyrics(lines: []);
    }

    final rawLines = content['lines'];
    if (rawLines is! List) return const RichLyrics(lines: []);

    final parsedLines = <RichLyricLine>[];
    for (final rawLine in rawLines) {
      if (rawLine is! List || rawLine.length < 3) continue;
      final startSeconds = _number(rawLine[0]);
      final endSeconds = _number(rawLine[1]);
      final text = rawLine[2];
      if (startSeconds == null || endSeconds == null || text is! String) {
        continue;
      }

      final start = _durationFromSeconds(startSeconds);
      final end = _durationFromSeconds(endSeconds);
      if (end <= start || text.trim().isEmpty) continue;

      final timedSegments = <RichLyricWord>[];
      final rawWords = rawLine.length > 3 ? rawLine[3] : null;
      if (rawWords is List) {
        for (final rawWord in rawWords) {
          if (rawWord is! List || rawWord.length < 3) continue;
          final wordStart = _number(rawWord[0]);
          final wordEnd = _number(rawWord[1]);
          final wordText = rawWord[2];
          if (wordStart == null ||
              wordEnd == null ||
              wordText is! String ||
              wordText.trim().isEmpty) {
            continue;
          }
          final wordStartDuration = _durationFromSeconds(wordStart);
          final wordEndDuration = _durationFromSeconds(wordEnd);
          if (wordEndDuration <= wordStartDuration) continue;
          timedSegments.add(RichLyricWord(
            start: wordStartDuration,
            end: wordEndDuration,
            text: wordText.trim(),
          ));
        }
      }

      parsedLines.add(RichLyricLine(
        start: start,
        end: end,
        text: text,
        words: _mergeTimedSegments(text, timedSegments),
      ));
    }

    parsedLines.sort((a, b) => a.start.compareTo(b.start));
    return RichLyrics(
      title: _string(content['title']),
      artist: _string(content['artist']),
      duration: _durationFromSeconds(_number(content['duration'])),
      lines: parsedLines,
    );
  }

  bool get hasWordSync => lines.any((line) => line.words.isNotEmpty);

  /// Makes a renderable line list while retaining the source line indexes.
  ///
  /// A line timestamp cannot reveal the singer's word timing. The renderer uses
  /// a short fixed stagger instead: each word gets a zero-length activation
  /// 50ms after the previous one. That creates the same visual handoff as a
  /// word-timed line without claiming that the inferred timings are factual.
  factory RichLyrics.fromLyricLines(
    List<LyricLine> source, {
    Duration? songDuration,
  }) {
    final lines = <RichLyricLine>[];
    for (var index = 0; index < source.length; index++) {
      final line = source[index];
      if (!line.isSynced || line.text.trim().isEmpty) {
        lines.add(RichLyricLine(
          start: line.time,
          end: line.time,
          text: line.text,
        ));
        continue;
      }

      final nextTimed = _nextTimedLine(source, index);
      final end =
          nextTimed ?? songDuration ?? line.time + const Duration(seconds: 4);
      final lineEnd =
          end > line.time ? end : line.time + const Duration(seconds: 1);
      final words = _simulatedWords(line.text, line.time);
      lines.add(RichLyricLine(
        start: line.time,
        end: lineEnd,
        text: line.text,
        words: words,
        isSimulated: true,
      ));
    }
    return RichLyrics(duration: songDuration, lines: lines);
  }

  /// Converts a rich payload to LRC for the existing lyrics editor/apply flow.
  String toLrc() {
    return lines
        .where((line) => line.text.trim().isNotEmpty)
        .map((line) => '[${_formatTimestamp(line.start)}]${line.text}')
        .join('\n');
  }

  /// The rich API times syllables, while the lyric text contains whole words.
  /// Rebuild the display words from the source line so syllables such as
  /// `ig`, `nor`, and `ing,` never acquire artificial spaces or line breaks.
  static List<RichLyricWord> _mergeTimedSegments(
    String text,
    List<RichLyricWord> segments,
  ) {
    if (segments.isEmpty) return const [];

    final sourceWords = RegExp(r'\S+')
        .allMatches(text)
        .map((match) => match.group(0) ?? '')
        .where((word) => word.isNotEmpty)
        .toList();
    if (sourceWords.isEmpty) return segments;

    final merged = <RichLyricWord>[];
    var segmentIndex = 0;
    for (final sourceWord in sourceWords) {
      if (segmentIndex >= segments.length) break;

      final expected = _normaliseForMatching(sourceWord);
      final first = segments[segmentIndex];
      var last = first;
      var combined = '';
      var matched = false;

      while (segmentIndex < segments.length) {
        last = segments[segmentIndex];
        combined += last.text;
        segmentIndex++;
        final normalised = _normaliseForMatching(combined);
        if (normalised == expected || normalised.length >= expected.length) {
          matched = normalised == expected;
          break;
        }
      }

      // The source line is authoritative for display text. Even if a provider
      // has a punctuation or apostrophe variant, its segment timing still
      // covers one source word and should not make the word split visually.
      merged.add(RichLyricWord(
        start: first.start,
        end: last.end,
        text: sourceWord,
      ));

      // A malformed provider segment should not prevent the remaining source
      // words from being displayed, but keep the normal path explicit for
      // analyzers and future parser changes.
      if (!matched && segmentIndex >= segments.length) break;
    }

    return merged;
  }

  static String _normaliseForMatching(String value) {
    return value
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  static Duration? _nextTimedLine(List<LyricLine> source, int index) {
    for (var next = index + 1; next < source.length; next++) {
      if (source[next].isSynced) return source[next].time;
    }
    return null;
  }

  static List<RichLyricWord> _simulatedWords(String text, Duration start) {
    final tokens = RegExp(r'\S+').allMatches(text).toList();
    if (tokens.isEmpty) return const [];

    return [
      for (var index = 0; index < tokens.length; index++)
        RichLyricWord(
          start: start + Duration(milliseconds: index * 50),
          end: start + Duration(milliseconds: index * 50),
          text: tokens[index].group(0) ?? '',
        ),
    ];
  }

  static double? _number(Object? value) {
    return value is num ? value.toDouble() : null;
  }

  static Duration _durationFromSeconds(double? seconds) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite) {
      return Duration.zero;
    }
    return Duration(
        microseconds: (seconds * Duration.microsecondsPerSecond).round());
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static String _formatTimestamp(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    final centiseconds = (value.inMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
  }
}

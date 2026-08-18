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

  const RichLyricLine({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
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

      final words = <RichLyricWord>[];
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
              wordText.isEmpty) {
            continue;
          }
          final wordStartDuration = _durationFromSeconds(wordStart);
          final wordEndDuration = _durationFromSeconds(wordEnd);
          if (wordEndDuration <= wordStartDuration) continue;
          words.add(RichLyricWord(
            start: wordStartDuration,
            end: wordEndDuration,
            text: wordText,
          ));
        }
      }

      parsedLines.add(RichLyricLine(
        start: start,
        end: end,
        text: text,
        words: words,
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

  /// Makes a rich line list that retains the source line indexes.
  ///
  /// Better Lyrics gives line-synced lyrics a small delay per word. The
  /// fallback uses the available line interval, weighted by word length, and
  /// adds deliberate pauses after commas and sentence punctuation. It is not
  /// presented as provider-accurate timing, but it feels natural while keeping
  /// every line's words moving with the song.
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
      final words = _fallbackWords(line.text, line.time, lineEnd);
      lines.add(RichLyricLine(
        start: line.time,
        end: lineEnd,
        text: line.text,
        words: words,
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

  static Duration? _nextTimedLine(List<LyricLine> source, int index) {
    for (var next = index + 1; next < source.length; next++) {
      if (source[next].isSynced) return source[next].time;
    }
    return null;
  }

  static List<RichLyricWord> _fallbackWords(
    String text,
    Duration start,
    Duration end,
  ) {
    final tokens = RegExp(r'\S+').allMatches(text).toList();
    if (tokens.isEmpty) return const [];

    final weights = <double>[];
    for (final token in tokens) {
      final value = token.group(0) ?? '';
      var weight = value.runes.length.clamp(1, 12).toDouble();
      if (RegExp(r'[,;:]$').hasMatch(value)) weight += 2.5;
      if (RegExp(r'[.!?]$').hasMatch(value)) weight += 4.0;
      weights.add(weight);
    }

    final totalWeight = weights.fold<double>(0, (sum, value) => sum + value);
    final spanMs = (end - start).inMilliseconds;
    if (totalWeight <= 0 || spanMs <= 0) return const [];

    final words = <RichLyricWord>[];
    var elapsedWeight = 0.0;
    for (var index = 0; index < tokens.length; index++) {
      final wordStart = start +
          Duration(
            milliseconds: (spanMs * elapsedWeight / totalWeight).round(),
          );
      elapsedWeight += weights[index];
      final wordEnd = start +
          Duration(
            milliseconds: (spanMs * elapsedWeight / totalWeight).round(),
          );
      final safeEnd = wordEnd > wordStart
          ? wordEnd
          : wordStart + const Duration(milliseconds: 50);
      words.add(RichLyricWord(
        start: wordStart,
        end: safeEnd,
        text: tokens[index].group(0) ?? '',
      ));
    }
    return words;
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

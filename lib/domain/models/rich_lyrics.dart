import 'dart:math' as math;

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
  /// For line-synced sources, infers realistic word pacing from the song's
  /// overall cadence, syllables, and punctuation rather than stretching short
  /// lines across long gaps.
  factory RichLyrics.fromLyricLines(
    List<LyricLine> source, {
    Duration? songDuration,
  }) {
    final lines = <RichLyricLine>[];
    final songCps = _estimateSongCadence(source);

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
      final words = _simulatedWords(
        line.text,
        line.time,
        lineEnd,
        songCps: songCps,
      );
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

  static double _estimateSongCadence(List<LyricLine> source) {
    final speeds = <double>[];
    for (var index = 0; index < source.length; index++) {
      final line = source[index];
      if (!line.isSynced) continue;
      final nextTimed = _nextTimedLine(source, index);
      if (nextTimed == null) continue;

      final deltaSeconds = (nextTimed - line.time).inMicroseconds / 1000000.0;
      if (deltaSeconds < 0.6 || deltaSeconds > 6.5) continue;

      final cleanChars = line.text.replaceAll(RegExp(r'\s+'), '').length;
      if (cleanChars >= 3) {
        speeds.add(cleanChars / deltaSeconds);
      }
    }

    if (speeds.isEmpty) return 13.5;

    speeds.sort();
    final median = speeds[speeds.length ~/ 2];
    return median.clamp(8.0, 22.0);
  }

  static int _estimateSyllables(String word) {
    var syllables = 0;
    final latinBuffer = StringBuffer();

    for (final rune in word.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3040 && rune <= 0x309F) ||
          (rune >= 0x30A0 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF)) {
        syllables++;
      } else {
        latinBuffer.writeCharCode(rune);
      }
    }

    final latin =
        latinBuffer.toString().toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
    if (latin.isNotEmpty) {
      var count = 0;
      var inVowels = false;
      const vowels = {'a', 'e', 'i', 'o', 'u', 'y'};

      for (var i = 0; i < latin.length; i++) {
        final char = latin[i];
        final isVowel = vowels.contains(char);
        if (isVowel && !inVowels) {
          count++;
          inVowels = true;
        } else if (!isVowel) {
          inVowels = false;
        }
      }

      if (count > 1 && latin.endsWith('e') && !latin.endsWith('le')) {
        count--;
      }

      syllables += math.max(1, count);
    }

    return math.max(1, syllables);
  }

  static List<RichLyricWord> _simulatedWords(
    String text,
    Duration start,
    Duration end, {
    double songCps = 13.5,
  }) {
    final tokens = RegExp(r'\S+').allMatches(text).toList();
    if (tokens.isEmpty) return const [];

    final lineDurationUs = (end - start).inMicroseconds;
    if (lineDurationUs <= 0) {
      return [
        for (var index = 0; index < tokens.length; index++)
          RichLyricWord(
            start: start + Duration(milliseconds: index * 50),
            end: start + Duration(milliseconds: (index + 1) * 50),
            text: tokens[index].group(0) ?? '',
          ),
      ];
    }

    final totalCleanChars = text.replaceAll(RegExp(r'\s+'), '').length;
    var totalSyllables = 0;
    final tokenWeights = <int>[];
    final tokenPausesUs = <int>[];

    for (final token in tokens) {
      final str = token.group(0) ?? '';
      final syl = _estimateSyllables(str);
      totalSyllables += syl;

      final cleanLen = str.replaceAll(RegExp(r'[^\w]'), '').length;
      final weight = (syl * 3) + math.max<int>(1, cleanLen);
      tokenWeights.add(weight);

      var pauseUs = 0;
      if (str.endsWith(',') ||
          str.endsWith(';') ||
          str.endsWith('-') ||
          str.endsWith('~')) {
        pauseUs = 80000;
      } else if (str.endsWith('.') || str.endsWith('!') || str.endsWith('?')) {
        pauseUs = 120000;
      }
      tokenPausesUs.add(pauseUs);
    }

    final totalWeight = tokenWeights.fold<int>(0, (sum, w) => sum + w);
    final totalPauseUs = tokenPausesUs.fold<int>(0, (sum, p) => sum + p);

    final expectedFromCharsUs = ((totalCleanChars / songCps) * 1000000).round();
    final sylSec = songCps > 16.0 ? 0.20 : (songCps < 10.0 ? 0.32 : 0.26);
    final expectedFromSyllablesUs =
        ((totalSyllables * sylSec) * 1000000).round();
    final expectedVocalUs =
        ((expectedFromCharsUs * 0.65) + (expectedFromSyllablesUs * 0.35))
            .round();

    final minVocalUs =
        math.max(tokens.length * 180000, totalCleanChars * 45000);
    final maxVocalUs = math.max(minVocalUs, (expectedVocalUs * 1.35).round());

    int vocalSpanUs;
    if (lineDurationUs <= expectedVocalUs + 400000) {
      final breathUs = ((lineDurationUs * 0.08).round()).clamp(50000, 300000);
      final upperBound = math.max(minVocalUs, lineDurationUs);
      vocalSpanUs = (lineDurationUs - breathUs).clamp(minVocalUs, upperBound);
    } else {
      final maxAvailableUs =
          math.max(minVocalUs, math.min(lineDurationUs - 400000, maxVocalUs));
      vocalSpanUs = expectedVocalUs.clamp(minVocalUs, maxAvailableUs);
    }

    final allocatableUs = math.max(0, vocalSpanUs - totalPauseUs);
    var cursorUs = 0;
    final words = <RichLyricWord>[];

    for (var i = 0; i < tokens.length; i++) {
      final wordText = tokens[i].group(0) ?? '';
      final wordWeight = tokenWeights[i];
      final wordDurationUs = totalWeight > 0
          ? (allocatableUs * wordWeight / totalWeight).round()
          : (allocatableUs / tokens.length).round();

      final wordStart = start + Duration(microseconds: cursorUs);
      final wordEnd = wordStart + Duration(microseconds: wordDurationUs);
      cursorUs += wordDurationUs + tokenPausesUs[i];

      words.add(RichLyricWord(
        start: wordStart,
        end: wordEnd,
        text: wordText,
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

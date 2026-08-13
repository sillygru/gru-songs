import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class TranslationResponse {
  final String text;
  final String? detectedSourceLang;

  const TranslationResponse({
    required this.text,
    this.detectedSourceLang,
  });
}

/// Translation service that races multiple keyless backends in parallel and
/// keeps the first successful reply. Batches for a single lyrics payload also
/// run concurrently so long tracks do not wait on a serial waterfall.
class LingvaTranslateService {
  static const List<String> defaultHosts = [
    'lingva.ml',
    'lingva.lunar.icu',
    'translate.plausibility.cloud',
    'lingva.garudalinux.org',
  ];

  static const Duration _timeout = Duration(seconds: 8);
  static const int _maxBatchChars = 1800;
  static const int _myMemoryMaxChars = 450;

  final List<String> hosts;

  LingvaTranslateService({List<String>? hosts}) : hosts = hosts ?? defaultHosts;

  String get host => hosts.first;

  /// Script range for non-Latin [targetLang]s, or null for Latin-script
  /// targets (en, es, fr, de, ...) where script detection cannot tell English
  /// from French — those rely on the backend's auto-detect instead.
  static RegExp? _scriptFor(String targetLang) {
    switch (targetLang.toLowerCase()) {
      case 'ja':
        return RegExp(r'[\u3040-\u30ff\u4e00-\u9faf]');
      case 'ko':
        return RegExp(r'[\uac00-\ud7af]');
      case 'zh':
        return RegExp(r'[\u4e00-\u9faf]');
      case 'ru':
      case 'uk':
        return RegExp(r'[\u0400-\u04ff]');
      case 'ar':
        return RegExp(r'[\u0600-\u06ff]');
      case 'hi':
        return RegExp(r'[\u0900-\u097f]');
      case 'el':
        return RegExp(r'[\u0370-\u03ff]');
      case 'th':
        return RegExp(r'[\u0e00-\u0e7f]');
      default:
        return null;
    }
  }

  /// Fast offline check to determine if text is already in [targetLang] script.
  bool isAlreadyInTargetScript(String text, String targetLang) {
    if (text.trim().isEmpty) return false;
    final script = _scriptFor(targetLang);
    if (script == null) return false;
    return script.allMatches(text).length > 10;
  }

  /// Any character outside the Latin range, digits, whitespace and Unicode
  /// punctuation/symbols marks a foreign script. Emoji, numbers and full-width
  /// punctuation are excluded so a stray symbol never flags a line.
  static final RegExp _foreignScript = RegExp(
    r'[^\u0000-\u024F\s\d\p{P}\p{S}]',
    unicode: true,
  );

  /// Whether [line] carries enough non-Latin characters to count as not being
  /// written in a Latin-script language. The threshold is low on purpose: a
  /// mostly-English line that dips into kana should still be translated.
  @visibleForTesting
  static bool hasSignificantForeignScript(String line) {
    return _foreignScript.allMatches(line).length >= 3;
  }

  /// Whether [line] must be translated before it can count as already in
  /// [targetLang].
  ///
  /// Non-Latin targets are matched by script: a line is already in the target
  /// when a clear majority of its characters are written in that script.
  /// Latin-script targets cannot be told apart offline, so the rule inverts —
  /// a line with significant foreign script needs translation, a Latin line is
  /// assumed to already be in the target.
  @visibleForTesting
  static bool lineNeedsTranslation(String line, String targetLang) {
    final script = _scriptFor(targetLang);
    if (script == null) return hasSignificantForeignScript(line);
    final count = script.allMatches(line).length;
    if (count == 0) return true;
    // Majority script wins: a line that is mostly kana/kanji is already in
    // Japanese, one that only dips into it still needs translating. A pure
    // count threshold would send short all-target lines to the backend too,
    // letting them skew the batch's auto-detected language.
    final meaningful = line.replaceAll(RegExp(r'\s', unicode: true), '').length;
    return count / meaningful < 0.5;
  }

  /// Splices translated lines back into their original positions. Entries that
  /// did not need translation (already in the target language) keep their
  /// original text; [translatedLines] must hold exactly one entry per line
  /// that did need translating, in order.
  @visibleForTesting
  static List<String> spliceTranslations({
    required List<String> originalLines,
    required List<bool>? needsTranslation,
    required List<String> translatedLines,
  }) {
    final result = <String>[];
    var cursor = 0;
    for (int i = 0; i < originalLines.length; i++) {
      if (needsTranslation != null &&
          i < needsTranslation.length &&
          !needsTranslation[i]) {
        result.add(originalLines[i]);
      } else if (cursor < translatedLines.length) {
        result.add(translatedLines[cursor++]);
      } else {
        // A malformed backend response must not shift or delete later lines.
        result.add(originalLines[i]);
      }
    }
    return result;
  }

  /// Translates raw lyrics text (LRC format or plain text) into [targetLang].
  /// Preserves LRC timestamps ([mm:ss.xx]), metadata headers ([ar:..]),
  /// and line alignment.
  ///
  /// Non-Latin lines that are confidently already in the target script are
  /// kept locally. Latin-script lines are sent because English, Spanish,
  /// French, and similar languages cannot be distinguished by script alone.
  /// Batches are split when their scripts change, then spliced back into the
  /// original positions.
  Future<TranslationResponse> translateLyrics({
    required String lyrics,
    required String targetLang,
    String sourceLang = 'auto',
  }) async {
    if (lyrics.trim().isEmpty) {
      return TranslationResponse(text: lyrics);
    }

    final lines = lyrics.split('\n');
    final List<String?> resultLines = List.filled(lines.length, null);
    final List<_PendingLine> pendingTextLines = [];

    final timeExp = RegExp(r'^((?:\[[0-9]+:[0-9]+\.?[0-9]*\])+)(.*)$');
    final metaExp = RegExp(r'^\[[a-zA-Z]+:.+\]$');

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i].trimRight();
      final lineText = rawLine.trim();

      if (lineText.isEmpty) {
        resultLines[i] = rawLine;
        continue;
      }

      if (metaExp.hasMatch(lineText)) {
        resultLines[i] = rawLine;
        continue;
      }

      final timeMatch = timeExp.firstMatch(lineText);
      if (timeMatch != null) {
        final timePrefix = timeMatch.group(1) ?? '';
        final contentText = (timeMatch.group(2) ?? '').trim();
        if (contentText.isEmpty) {
          resultLines[i] = rawLine;
        } else {
          pendingTextLines.add(_PendingLine(
            index: i,
            timePrefix: timePrefix,
            text: contentText,
          ));
        }
      } else {
        pendingTextLines.add(_PendingLine(
          index: i,
          timePrefix: '',
          text: lineText,
        ));
      }
    }

    if (pendingTextLines.isEmpty) {
      return TranslationResponse(text: lyrics);
    }

    // Script detection can identify target-language lines for non-Latin
    // targets. Latin-script languages cannot be distinguished reliably without
    // a language detector, so every line is sent to the translator; a line
    // already in Spanish, for example, is safely returned as Spanish instead
    // of being mistaken for English and left untranslated.
    final targetScript = _scriptFor(targetLang);
    final needsTranslation = targetScript == null
        ? List<bool>.filled(pendingTextLines.length, true)
        : [
            for (final p in pendingTextLines)
              lineNeedsTranslation(p.text, targetLang),
          ];

    if (!needsTranslation.any((needs) => needs)) {
      return TranslationResponse(
        text: lyrics,
        detectedSourceLang: targetLang.toLowerCase(),
      );
    }

    final toTranslate = <_PendingLine>[];
    for (int i = 0; i < pendingTextLines.length; i++) {
      if (needsTranslation[i]) {
        toTranslate.add(pendingTextLines[i]);
      }
    }

    final batches = _createBatches(toTranslate);

    // Translate every batch concurrently; each batch races its backends.
    final batchResults = await Future.wait(
      batches.map(
        (batch) => _translateBatch(
          batch: batch,
          targetLang: targetLang,
          sourceLang: sourceLang,
        ),
      ),
    );

    String? detectedSource;
    for (final batchResult in batchResults) {
      detectedSource ??= batchResult.detectedSourceLang;
    }

    // The translated lines come back in the same order they were sent; kept
    // lines (already in the target language) retain their original text.
    final translatedLines = <String>[
      for (final batchResult in batchResults) ...batchResult.lines,
    ];
    final spliced = spliceTranslations(
      originalLines: [
        for (final p in pendingTextLines) '${p.timePrefix}${p.text}',
      ],
      needsTranslation: needsTranslation,
      translatedLines: translatedLines,
    );
    for (int i = 0; i < pendingTextLines.length; i++) {
      resultLines[pendingTextLines[i].index] = spliced[i];
    }

    final fullText = resultLines.whereType<String>().join('\n');
    return TranslationResponse(
      text: fullText,
      detectedSourceLang: detectedSource,
    );
  }

  List<List<_PendingLine>> _createBatches(List<_PendingLine> items) {
    final List<List<_PendingLine>> batches = [];
    List<_PendingLine> currentBatch = [];
    int currentChars = 0;
    String? currentScript;

    for (final item in items) {
      final itemLen = item.text.length + 1;
      final itemScript = _scriptBucket(item.text);
      final scriptChanged =
          currentScript != null && currentScript != itemScript;
      if (currentBatch.isNotEmpty &&
          (scriptChanged || currentChars + itemLen > _maxBatchChars)) {
        batches.add(currentBatch);
        currentBatch = [];
        currentChars = 0;
        currentScript = null;
      }
      currentBatch.add(item);
      currentChars += itemLen;
      currentScript ??= itemScript;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    return batches;
  }

  String _scriptBucket(String text) {
    if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    if (RegExp(r'[\u4e00-\u9faf]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(text)) return 'cyrillic';
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(text)) return 'arabic';
    if (RegExp(r'[\u0900-\u097f]').hasMatch(text)) return 'devanagari';
    if (RegExp(r'[\u0370-\u03ff]').hasMatch(text)) return 'greek';
    if (RegExp(r'[\u0e00-\u0e7f]').hasMatch(text)) return 'thai';
    return 'latin';
  }

  Future<_BatchResult> _translateBatch({
    required List<_PendingLine> batch,
    required String targetLang,
    required String sourceLang,
  }) async {
    final batchText = batch.map((b) => b.text).join('\n');
    final fetchResult = await _raceTranslation(
      query: batchText,
      targetLang: targetLang,
      sourceLang: sourceLang,
    );

    final splitLines = fetchResult.text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    // Translation endpoints are not consistent about preserving newlines. Do
    // not shift every following lyric when one endpoint collapses a line: fall
    // back to one request per line, where the response cannot be ambiguous.
    if (splitLines.length != batch.length) {
      final individualResults = await Future.wait(
        batch.map(
          (item) => _raceTranslation(
            query: item.text,
            targetLang: targetLang,
            sourceLang: sourceLang,
          ),
        ),
      );
      return _BatchResult(
        lines: [
          for (int i = 0; i < batch.length; i++)
            _cleanTranslatedLine(
              individualResults[i].text,
              batch[i].text,
            ),
        ],
        detectedSourceLang: individualResults
            .map((result) => result.detectedSourceLang)
            .firstWhere((lang) => lang != null, orElse: () => null),
      );
    }

    return _BatchResult(
      lines: [
        for (int i = 0; i < batch.length; i++)
          _cleanTranslatedLine(splitLines[i], batch[i].text),
      ],
      detectedSourceLang: fetchResult.detectedSourceLang,
    );
  }

  String _cleanTranslatedLine(String translated, String fallback) {
    final cleaned = translated.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// Fires every keyless backend at once and keeps the first usable reply.
  Future<TranslationResponse> _raceTranslation({
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final completer = Completer<TranslationResponse>();
    final clients = <HttpClient>[];
    var failures = 0;
    Object? lastError;

    late final List<Future<TranslationResponse> Function(HttpClient)> starters;

    starters = [
      for (final h in hosts)
        (client) => _fetchFromLingvaHost(
              client: client,
              host: h,
              query: query,
              targetLang: targetLang,
              sourceLang: sourceLang,
            ),
      (client) => _fetchFromGTX(
            client: client,
            query: query,
            targetLang: targetLang,
            sourceLang: sourceLang,
          ),
      (client) => _fetchFromGoogleClients5(
            client: client,
            query: query,
            targetLang: targetLang,
            sourceLang: sourceLang,
          ),
      if (query.length <= _myMemoryMaxChars)
        (client) => _fetchFromMyMemory(
              client: client,
              query: query,
              targetLang: targetLang,
              sourceLang: sourceLang,
            ),
    ];

    void settleFailure(Object error) {
      lastError = error;
      failures += 1;
      if (failures >= starters.length && !completer.isCompleted) {
        completer.completeError(
          HttpException(
            'Translation service unavailable: ${lastError ?? "all translation endpoints failed"}',
          ),
        );
      }
    }

    void settleSuccess(TranslationResponse result) {
      if (completer.isCompleted) return;
      if (result.text.trim().isEmpty) {
        settleFailure(const FormatException('Empty translation'));
        return;
      }
      completer.complete(result);
      for (final client in clients) {
        client.close(force: true);
      }
    }

    for (final start in starters) {
      final client = HttpClient()..connectionTimeout = _timeout;
      clients.add(client);
      start(client).then<void>(
        settleSuccess,
        onError: settleFailure,
      );
    }

    try {
      return await completer.future.timeout(_timeout);
    } on TimeoutException {
      for (final client in clients) {
        client.close(force: true);
      }
      throw HttpException(
        'Translation service unavailable: ${lastError ?? "timed out"}',
      );
    } finally {
      // Losers may still be mid-flight after a successful race; close them so
      // sockets do not linger until the OS timeout.
      if (completer.isCompleted) {
        for (final client in clients) {
          client.close(force: true);
        }
      }
    }
  }

  Future<TranslationResponse> _fetchFromLingvaHost({
    required HttpClient client,
    required String host,
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final encodedSource = Uri.encodeComponent(sourceLang);
    final encodedTarget = Uri.encodeComponent(targetLang);
    final encodedQuery = Uri.encodeComponent(query);

    final uri = Uri(
      scheme: 'https',
      host: host,
      path: '/api/v1/$encodedSource/$encodedTarget/$encodedQuery',
    );

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'WispieMusicPlayer/1.0');

    final response = await request.close().timeout(_timeout);

    if (response.statusCode != 200) {
      throw HttpException('Lingva HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;

    final translation = data['translation'] as String?;
    if (translation == null) {
      throw const FormatException('Missing translation field in response');
    }

    String? detected;
    final info = data['info'];
    if (info is Map && info['detectedSource'] is String) {
      detected = info['detectedSource'] as String;
    }

    return TranslationResponse(text: translation, detectedSourceLang: detected);
  }

  Future<TranslationResponse> _fetchFromGTX({
    required HttpClient client,
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final encodedSource = Uri.encodeComponent(sourceLang);
    final encodedTarget = Uri.encodeComponent(targetLang);
    final encodedQuery = Uri.encodeComponent(query);

    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$encodedSource&tl=$encodedTarget&dt=t&q=$encodedQuery',
    );

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');

    final response = await request.close().timeout(_timeout);

    if (response.statusCode != 200) {
      throw HttpException('GTX HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final List<dynamic> data = jsonDecode(body) as List<dynamic>;

    if (data.isEmpty || data.first == null || data.first is! List) {
      throw const FormatException('Invalid GTX translation format');
    }

    final List<dynamic> segments = data.first as List<dynamic>;
    final StringBuffer buffer = StringBuffer();

    for (final segment in segments) {
      if (segment is List && segment.isNotEmpty && segment.first is String) {
        buffer.write(segment.first as String);
      }
    }

    String? detected;
    if (data.length > 2 && data[2] is String) {
      detected = data[2] as String;
    }

    return TranslationResponse(
      text: buffer.toString(),
      detectedSourceLang: detected,
    );
  }

  /// Alternate Google free endpoint used by Chrome's dictionary extension.
  Future<TranslationResponse> _fetchFromGoogleClients5({
    required HttpClient client,
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final uri = Uri.https(
      'clients5.google.com',
      '/translate_a/t',
      {
        'client': 'dict-chrome-ex',
        'sl': sourceLang,
        'tl': targetLang,
        'q': query,
      },
    );

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');

    final response = await request.close().timeout(_timeout);

    if (response.statusCode != 200) {
      throw HttpException('Clients5 HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final dynamic data = jsonDecode(body);

    final buffer = StringBuffer();
    String? detected;

    if (data is List && data.isNotEmpty) {
      // Typical shape: [["translated","sourceLang"], ...] or
      // [[["translated", ...], ...], "sourceLang"]
      final first = data.first;
      if (first is List) {
        for (final item in data) {
          if (item is List && item.isNotEmpty && item.first is String) {
            buffer.write(item.first as String);
            if (item.length > 1 && item[1] is String) {
              detected ??= item[1] as String;
            }
          }
        }
      } else if (first is String) {
        buffer.write(first);
      }
      if (data.length > 1 && data[1] is String) {
        detected ??= data[1] as String;
      }
    } else {
      throw const FormatException('Invalid Clients5 translation format');
    }

    return TranslationResponse(
      text: buffer.toString(),
      detectedSourceLang: detected,
    );
  }

  Future<TranslationResponse> _fetchFromMyMemory({
    required HttpClient client,
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final source = sourceLang == 'auto' ? 'Autodetect' : sourceLang;
    final uri = Uri.https(
      'api.mymemory.translated.net',
      '/get',
      {
        'q': query,
        'langpair': '$source|$targetLang',
      },
    );

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'WispieMusicPlayer/1.0');

    final response = await request.close().timeout(_timeout);

    if (response.statusCode != 200) {
      throw HttpException('MyMemory HTTP ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;

    final responseData = data['responseData'];
    if (responseData is! Map) {
      throw const FormatException('Invalid MyMemory response');
    }

    final translated = responseData['translatedText'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      throw const FormatException('Empty MyMemory translation');
    }

    // MyMemory echoes MACHINE_ONLY / INVALID when it cannot translate.
    if (translated.contains('MYMEMORY WARNING') ||
        translated == 'INVALID SOURCE LANGUAGE' ||
        translated == 'PLEASE SELECT TWO DISTINCT LANGUAGES') {
      throw FormatException('MyMemory rejected query: $translated');
    }

    return TranslationResponse(text: translated);
  }
}

class _BatchResult {
  final List<String> lines;
  final String? detectedSourceLang;

  const _BatchResult({
    required this.lines,
    this.detectedSourceLang,
  });
}

class _PendingLine {
  final int index;
  final String timePrefix;
  final String text;

  const _PendingLine({
    required this.index,
    required this.timePrefix,
    required this.text,
  });
}

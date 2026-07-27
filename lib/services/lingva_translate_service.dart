import 'dart:convert';
import 'dart:io';

class TranslationResponse {
  final String text;
  final String? detectedSourceLang;

  const TranslationResponse({
    required this.text,
    this.detectedSourceLang,
  });
}

/// Translation service utilizing Lingva Translate API with automatic fallback
/// to Google Translate GTX endpoint for ultra-fast, robust translations.
class LingvaTranslateService {
  static const List<String> defaultHosts = [
    'lingva.ml',
    'lingva.lunar.icu',
  ];
  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxBatchChars = 2500;

  final List<String> hosts;

  LingvaTranslateService({List<String>? hosts}) : hosts = hosts ?? defaultHosts;

  String get host => hosts.first;

  /// Fast offline check to determine if text is already in [targetLang] script.
  bool isAlreadyInTargetScript(String text, String targetLang) {
    if (text.trim().isEmpty) return false;

    switch (targetLang.toLowerCase()) {
      case 'ja':
        final matchCount =
            RegExp(r'[\u3040-\u30ff\u4e00-\u9faf]').allMatches(text).length;
        return matchCount > 10;
      case 'ko':
        final matchCount = RegExp(r'[\uac00-\ud7af]').allMatches(text).length;
        return matchCount > 10;
      case 'zh':
        final matchCount = RegExp(r'[\u4e00-\u9faf]').allMatches(text).length;
        return matchCount > 10;
      case 'ru':
      case 'uk':
        final matchCount = RegExp(r'[\u0400-\u04ff]').allMatches(text).length;
        return matchCount > 10;
      case 'ar':
        final matchCount = RegExp(r'[\u0600-\u06ff]').allMatches(text).length;
        return matchCount > 10;
      case 'hi':
        final matchCount = RegExp(r'[\u0900-\u097f]').allMatches(text).length;
        return matchCount > 10;
      case 'el':
        final matchCount = RegExp(r'[\u0370-\u03ff]').allMatches(text).length;
        return matchCount > 10;
      default:
        return false;
    }
  }

  /// Translates raw lyrics text (LRC format or plain text) into [targetLang].
  /// Preserves LRC timestamps ([mm:ss.xx]), metadata headers ([ar:..]),
  /// and line alignment.
  Future<TranslationResponse> translateLyrics({
    required String lyrics,
    required String targetLang,
    String sourceLang = 'auto',
  }) async {
    if (lyrics.trim().isEmpty) {
      return TranslationResponse(text: lyrics);
    }

    if (isAlreadyInTargetScript(lyrics, targetLang)) {
      return TranslationResponse(
        text: lyrics,
        detectedSourceLang: targetLang.toLowerCase(),
      );
    }

    final lines = lyrics.split('\n');
    final List<String?> resultLines = List.filled(lines.length, null);
    final List<_PendingLine> pendingTextLines = [];

    // Step 1: Parse lines and categorize (metadata, empty, text)
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
        final timePrefix = timeMatch.group(1)!;
        final contentText = timeMatch.group(2)!.trim();
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

    // Step 2: Chunk text lines into safe batches
    final batches = _createBatches(pendingTextLines);
    String? detectedSource;

    // Step 3: Translate batches via Lingva / GTX API
    for (final batch in batches) {
      final batchResult = await _translateBatch(
        batch: batch,
        targetLang: targetLang,
        sourceLang: sourceLang,
      );

      detectedSource ??= batchResult.detectedSourceLang;

      for (int k = 0; k < batch.length; k++) {
        final item = batch[k];
        final translated = batchResult.lines[k];
        resultLines[item.index] = '${item.timePrefix}$translated';
      }
    }

    // Step 4: Reassemble lines
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

    for (final item in items) {
      final itemLen = item.text.length + 1;
      if (currentBatch.isNotEmpty &&
          (currentChars + itemLen > _maxBatchChars)) {
        batches.add(currentBatch);
        currentBatch = [];
        currentChars = 0;
      }
      currentBatch.add(item);
      currentChars += itemLen;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    return batches;
  }

  Future<_BatchResult> _translateBatch({
    required List<_PendingLine> batch,
    required String targetLang,
    required String sourceLang,
  }) async {
    final batchText = batch.map((b) => b.text).join('\n');
    final fetchResult = await _fetchTranslationWithFallback(
      query: batchText,
      targetLang: targetLang,
      sourceLang: sourceLang,
    );

    final splitLines = fetchResult.text.split('\n');

    final List<String> mappedResults = [];
    for (int i = 0; i < batch.length; i++) {
      if (i < splitLines.length && splitLines[i].trim().isNotEmpty) {
        mappedResults.add(splitLines[i].trim());
      } else {
        mappedResults.add(batch[i].text);
      }
    }

    return _BatchResult(
      lines: mappedResults,
      detectedSourceLang: fetchResult.detectedSourceLang,
    );
  }

  Future<TranslationResponse> _fetchTranslationWithFallback({
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    Object? lastError;

    // 1. Try Lingva hosts
    for (final h in hosts) {
      try {
        final result = await _fetchFromLingvaHost(
          host: h,
          query: query,
          targetLang: targetLang,
          sourceLang: sourceLang,
        );
        if (result.text.trim().isNotEmpty) {
          return result;
        }
      } catch (e) {
        lastError = e;
      }
    }

    // 2. Fallback to GTX Endpoint (Google Translate free engine)
    try {
      final result = await _fetchFromGTX(
        query: query,
        targetLang: targetLang,
        sourceLang: sourceLang,
      );
      if (result.text.trim().isNotEmpty) {
        return result;
      }
    } catch (e) {
      lastError = e;
    }

    throw HttpException(
      'Translation service unavailable: ${lastError ?? "all translation endpoints failed"}',
    );
  }

  Future<TranslationResponse> _fetchFromLingvaHost({
    required String host,
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = _timeout;

    try {
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
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> data = jsonDecode(body);

      final translation = data['translation'] as String?;
      if (translation == null) {
        throw const FormatException('Missing translation field in response');
      }

      String? detected;
      if (data['info'] is Map && data['info']['detectedSource'] is String) {
        detected = data['info']['detectedSource'] as String;
      }

      return TranslationResponse(
          text: translation, detectedSourceLang: detected);
    } finally {
      client.close();
    }
  }

  Future<TranslationResponse> _fetchFromGTX({
    required String query,
    required String targetLang,
    required String sourceLang,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = _timeout;

    try {
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
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final List<dynamic> data = jsonDecode(body);

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
    } finally {
      client.close();
    }
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

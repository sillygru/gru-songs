import 'dart:async';
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

    final batches = _createBatches(pendingTextLines);

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
    for (int i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final batchResult = batchResults[i];
      detectedSource ??= batchResult.detectedSourceLang;

      for (int k = 0; k < batch.length; k++) {
        final item = batch[k];
        final translated = batchResult.lines[k];
        resultLines[item.index] = '${item.timePrefix}$translated';
      }
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
    final fetchResult = await _raceTranslation(
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

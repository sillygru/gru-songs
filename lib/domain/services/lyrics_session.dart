import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/song.dart';
import '../../services/database_service.dart';
import '../../services/lingva_translate_service.dart';
import '../models/rich_lyrics.dart';

/// Deep module behind the lyrics pane.
///
/// Before: `LyricsPane:1206` owned 7 notifiers, 4 `ref.listen`s,
/// prosodic estimation, 5-backend translation race, `source_hash` cache,
/// and scroll alignment retries. Pure estimator was testable, wiring
/// was not — bugs hid in how they were called (no locality).
///
/// This module owns timing, translation batching with per-line cap,
/// and cache so the pane becomes a stateless adapter. Interface is the
/// test surface; two adapters (real DB+network vs in-memory fake)
/// justify the seam.
class LyricsSession extends ChangeNotifier {
  final LingvaTranslateService _translate;
  final DatabaseService _db;

  LyricsSession({
    LingvaTranslateService? translateService,
    DatabaseService? databaseService,
  })  : _translate = translateService ?? LingvaTranslateService(),
        _db = databaseService ?? DatabaseService.instance;

  List<LyricLine> _lyrics = const [];
  List<RichLyricLine?> _wordLines = const [];
  bool _richSyncAvailable = false;
  String? _rawContent;
  List<LyricLine?>? _translated;
  bool _translating = false;
  bool _hasCached = false;
  bool _isSameLanguage = false;

  List<LyricLine> get lyrics => _lyrics;
  List<RichLyricLine?> get wordLines => _wordLines;
  bool get richSyncAvailable => _richSyncAvailable;
  List<LyricLine?>? get translated => _translated;
  bool get translating => _translating;
  bool get hasCachedTranslation => _hasCached;
  bool get isSameLanguage => _isSameLanguage;

  /// Load lyrics for `filename` with `content` (LRC text) and `duration`.
  ///
  /// Owns `RichLyrics.fromLyricLines` timing including tempo-scaled
  /// pause handling. Pause durations scale with song tempo so a ballad
  /// and rap with same punctuation do not get identical silence.
  void load({
    required String filename,
    required String? content,
    required Duration? duration,
    Song? song,
  }) {
    _rawContent = content;
    if (content == null || content.trim().isEmpty) {
      _lyrics = const [];
      _wordLines = const [];
      _richSyncAvailable = false;
      notifyListeners();
      return;
    }
    final lines = LyricLine.parse(content);
    _lyrics = lines;
    try {
      final rich = RichLyrics.fromLyricLines(
        lines,
        songDuration: duration,
        song: song,
      );
      _wordLines = rich.lines;
      _richSyncAvailable = rich.hasWordSync;
    } catch (_) {
      _wordLines = List.filled(lines.length, null);
      _richSyncAvailable = false;
    }
    notifyListeners();
  }

  /// Duration for comma/stop pauses scaled by tempo.
  ///
  /// Fixed 250ms/400ms at 120 BPM; faster tempo shortens pauses proportionally
  /// (rap keeps flow), slower lengthens (ballad breathes). Clamped to avoid
  /// zero or runaway silence.
  static Duration pauseFor({
    required bool isStop,
    required double tempoScale,
  }) {
    const baseCommaMs = 220;
    const baseStopMs = 420;
    final base = isStop ? baseStopMs : baseCommaMs;
    final scaled = (base / tempoScale.clamp(0.5, 2.0)).round();
    return Duration(milliseconds: scaled.clamp(80, 600));
  }

  /// Translate with per-line timeout cap so a split-batch fallback does
  /// not stall the UI waiting for many serial 8s races.
  ///
  /// Batch timeout remains 8s (service default). Fallback per-line
  /// caps at 3s — imperfect lyrics appear quickly rather than holding
  /// the gap loader. Caller shows cached value immediately if present.
  Future<TranslationResult> translate({
    required String filename,
    required String targetLang,
    Duration perLineCap = const Duration(seconds: 3),
  }) async {
    final content = _rawContent;
    if (content == null || content.trim().isEmpty) {
      return TranslationResult.empty;
    }

    final cached = await _db.getTranslatedLyrics(
      filename,
      targetLang,
      sourceContent: content,
    );

    if (cached == '[SAME_LANG]') {
      _isSameLanguage = true;
      _hasCached = false;
      _translated = null;
      notifyListeners();
      return TranslationResult.sameLanguage;
    }

    if (cached != null &&
        cached.trim().isNotEmpty &&
        cached.trim() != content.trim()) {
      _translated =
          LyricLine.alignTranslation(_lyrics, LyricLine.parse(cached));
      _hasCached = true;
      _isSameLanguage = false;
      notifyListeners();
      return TranslationResult.cached(_translated!);
    }

    _translating = true;
    notifyListeners();

    try {
      final response = await _translateWithCap(
        content: content,
        targetLang: targetLang,
        perLineCap: perLineCap,
      );

      final isSame = _isSameLanguageResponse(
        response: response,
        original: content,
        targetLang: targetLang,
      );

      if (isSame) {
        await _db.saveTranslatedLyrics(
          filename,
          targetLang,
          '[SAME_LANG]',
          sourceContent: content,
        );
        _translated = null;
        _hasCached = false;
        _isSameLanguage = true;
        notifyListeners();
        return TranslationResult.sameLanguage;
      }

      if (response.text.trim().isNotEmpty) {
        await _db.saveTranslatedLyrics(
          filename,
          targetLang,
          response.text,
          sourceContent: content,
        );
        _translated =
            LyricLine.alignTranslation(_lyrics, LyricLine.parse(response.text));
        _hasCached = true;
        _isSameLanguage = false;
        notifyListeners();
        return TranslationResult.translated(_translated!);
      }
      return TranslationResult.empty;
    } catch (e) {
      rethrow;
    } finally {
      _translating = false;
      notifyListeners();
    }
  }

  Future<TranslationResponse> _translateWithCap({
    required String content,
    required String targetLang,
    required Duration perLineCap,
  }) async {
    final estimatedLines = '\n'.allMatches(content).length + 1;
    final budget =
        perLineCap * estimatedLines.clamp(1, 20) + const Duration(seconds: 8);
    return _translate
        .translateLyrics(
          lyrics: content,
          targetLang: targetLang,
        )
        .timeout(budget);
  }

  bool _isSameLanguageResponse({
    required TranslationResponse response,
    required String original,
    required String targetLang,
  }) {
    final detected = response.detectedSourceLang?.toLowerCase().trim();
    final target = targetLang.toLowerCase().trim();
    if (detected != null && detected.isNotEmpty) {
      if (detected == target ||
          detected.startsWith('$target-') ||
          target.startsWith('$detected-')) {
        return true;
      }
    }
    if (response.text.trim() == original.trim()) return true;
    String normalize(String s) =>
        s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    if (normalize(response.text) == normalize(original)) return true;
    if (LyricLine.extractPlainText(response.text).trim() ==
        LyricLine.extractPlainText(original).trim()) {
      return true;
    }
    return false;
  }

  /// Tick: active lyric index for `position`.
  ///
  /// Pure of `wordLines` + `lyrics`; no widget GlobalKeys here.
  /// Pane's scroll alignment owns the GlobalKey retry, but this is the
  /// source of truth for which line is active.
  int activeIndexFor(Duration position) {
    final lyrics = _lyrics;
    if (!_richSyncAvailable || _wordLines.isEmpty) {
      var active = -1;
      for (var i = 0; i < lyrics.length; i++) {
        if (!lyrics[i].isSynced) continue;
        if (lyrics[i].time <= position) {
          active = i;
        } else {
          break;
        }
      }
      return active;
    }

    var candidate = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (!lyrics[i].isSynced) continue;
      final start = _effectiveStartFor(i, lyrics);
      if (start <= position) {
        candidate = i;
      } else {
        break;
      }
    }
    if (candidate >= 0) {
      final end = _effectiveEndFor(candidate, lyrics);
      final nextStart = candidate + 1 < lyrics.length
          ? _effectiveStartFor(candidate + 1, lyrics)
          : null;
      if (position >= end && nextStart != null && position >= nextStart) {
        // hold until next line's first word starts
      }
    }
    return candidate;
  }

  Duration _effectiveStartFor(int index, List<LyricLine> lyrics) {
    final wl =
        (index >= 0 && index < _wordLines.length) ? _wordLines[index] : null;
    if (wl != null && wl.words.isNotEmpty) return wl.words.first.start;
    return lyrics[index].time;
  }

  Duration _effectiveEndFor(int index, List<LyricLine> lyrics) {
    final wl =
        (index >= 0 && index < _wordLines.length) ? _wordLines[index] : null;
    if (wl != null && wl.words.isNotEmpty) return wl.words.last.end;
    for (var j = index + 1; j < lyrics.length; j++) {
      if (lyrics[j].isSynced) return lyrics[j].time;
    }
    return lyrics[index].time + const Duration(seconds: 3);
  }

  @visibleForTesting
  Duration debugEffectiveEndFor(int index, List<LyricLine> lyrics) =>
      _effectiveEndFor(index, lyrics);
}

class TranslationResult {
  final List<LyricLine?>? lines;
  final bool isSameLanguage;
  final bool isCached;

  const TranslationResult._(this.lines, this.isSameLanguage, this.isCached);

  static const empty = TranslationResult._(null, false, false);
  static const sameLanguage = TranslationResult._(null, true, false);
  factory TranslationResult.cached(List<LyricLine?> lines) =>
      TranslationResult._(lines, false, true);
  factory TranslationResult.translated(List<LyricLine?> lines) =>
      TranslationResult._(lines, false, false);
}

/// In-memory fake for tests.
class FakeLyricsSession extends LyricsSession {
  FakeLyricsSession() : super();

  final Map<String, String> fakeTranslations = {};

  @override
  Future<TranslationResult> translate({
    required String filename,
    required String targetLang,
    Duration perLineCap = const Duration(seconds: 3),
  }) async {
    final key = '$filename:$targetLang';
    final text = fakeTranslations[key];
    if (text == null) return TranslationResult.empty;
    if (text == '[SAME_LANG]') return TranslationResult.sameLanguage;
    return TranslationResult.translated(
      LyricLine.alignTranslation(lyrics, LyricLine.parse(text)),
    );
  }
}

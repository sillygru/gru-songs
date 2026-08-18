import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../domain/models/lrclib_result.dart';
import '../domain/models/rich_lyrics.dart';
import '../domain/services/lrclib_match.dart';
import '../domain/services/lrclib_query.dart';
import '../models/song.dart';
import 'music_utils_api_client.dart';

/// Lyrics client with music-utils as the primary API and direct LRCLIB as a
/// fallback.
class LrclibService {
  static const String _host = 'lrclib.net';
  static const Duration _timeout = Duration(seconds: 8);

  static String? _userAgent;
  final MusicUtilsApiClient _musicUtils = MusicUtilsApiClient.instance;

  static const _placeholderTags = {
    'unknown title',
    'unknown artist',
    'unknown album',
  };

  static String? cleanTag(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || _placeholderTags.contains(v.toLowerCase())) return null;
    return v;
  }

  Future<List<LrclibResult>> findFor(
    Song song, {
    String? titleOverride,
    String? artistOverride,
    bool preferPlain = false,
  }) async {
    final artist = cleanTag(artistOverride ?? song.artist) ?? '';
    final album = cleanTag(song.album);
    final rawTitle = cleanTag(titleOverride ?? song.title) ?? '';
    final title = cleanSearchTitle(rawTitle, artist: artist);
    if (title.isEmpty && artist.isEmpty) return const [];

    final exactFuture = getExact(
      trackName: title,
      artistName: artist,
      albumName: album,
      duration: song.duration,
    );
    final searchFuture = search(trackName: title, artistName: artist);
    final exact = await exactFuture;
    var found = await searchFuture;
    if (found.isEmpty) {
      found = await searchFreeText(
        [title, artist].where((s) => s.isNotEmpty).join(' '),
      );
    }

    final merged = <int, LrclibResult>{};
    if (exact != null) merged[exact.id] = exact;
    for (final result in found) {
      merged.putIfAbsent(result.id, () => result);
    }

    return rankLrclibResults(
      merged.values.toList(),
      song,
      preferPlain: preferPlain,
    );
  }

  /// music-utils `/api/lyrics/get`, with direct LRCLIB fallback.
  Future<LrclibResult?> getExact({
    required String trackName,
    required String artistName,
    String? albumName,
    Duration? duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    final unified = await _musicUtils.getJson('/lyrics/get', {
      'track_name': trackName,
      'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      if (duration != null) 'duration': '${duration.inSeconds}',
      'include_rich_sync': 'true',
      'sync_type': 'richsync',
    });
    final unifiedResult = _resultFromObject(unified);
    if (unifiedResult != null) return unifiedResult;

    return _getExactDirect(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      duration: duration,
    );
  }

  /// Fetches the optional word/syllable payload without replacing local lyrics.
  /// A missing rich result is normal: callers should keep line-synced lyrics.
  Future<RichLyrics?> getRichSync(Song song) async {
    final trackName = cleanTag(song.title);
    final artistName = cleanTag(song.artist);
    if (trackName == null || artistName == null) return null;

    final decoded = await _musicUtils.getJson('/lyrics/get', {
      'track_name': cleanSearchTitle(trackName, artist: artistName),
      'artist_name': artistName,
      if (cleanTag(song.album) case final album?) 'album_name': album,
      if (song.duration case final duration?)
        'duration': '${duration.inSeconds}',
      'include_rich_sync': 'true',
      'sync_type': 'richsync',
    });
    final result = _resultFromObject(decoded);
    return result?.richLyrics;
  }

  /// music-utils `/api/lyrics/search`, with direct LRCLIB fallback.
  Future<List<LrclibResult>> search({
    required String trackName,
    String? artistName,
    String? albumName,
  }) async {
    if (trackName.isEmpty) return const [];

    final unified = await _musicUtils.getJson('/lyrics/search', {
      'track_name': trackName,
      if (artistName != null && artistName.isNotEmpty)
        'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      'limit': '20',
      'include_rich_sync': 'true',
      'sync_type': 'richsync',
    });
    final unifiedResults = _resultsFromObject(unified);
    if (unifiedResults.isNotEmpty) return unifiedResults;

    return _searchDirect({
      'track_name': trackName,
      if (artistName != null && artistName.isNotEmpty)
        'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
    });
  }

  /// music-utils free-text lyrics search, with direct LRCLIB fallback.
  Future<List<LrclibResult>> searchFreeText(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final unified = await _musicUtils.getJson('/lyrics/search', {
      'q': trimmed,
      'limit': '20',
      'include_rich_sync': 'true',
      'sync_type': 'richsync',
    });
    final unifiedResults = _resultsFromObject(unified);
    if (unifiedResults.isNotEmpty) return unifiedResults;

    return _searchDirect({'q': trimmed});
  }

  LrclibResult? _resultFromObject(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final result = LrclibResult.fromJson(decoded);
    return result.isUsable ? result : null;
  }

  List<LrclibResult> _resultsFromObject(Object? decoded) {
    if (decoded is! List) return const [];
    final results = <LrclibResult>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final result = LrclibResult.fromJson(entry);
      if (result.isUsable) results.add(result);
    }
    return results;
  }

  Future<LrclibResult?> _getExactDirect({
    required String trackName,
    required String artistName,
    String? albumName,
    Duration? duration,
  }) async {
    final decoded = await _getJson('/api/get', {
      'track_name': trackName,
      'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      if (duration != null) 'duration': '${duration.inSeconds}',
    });
    if (decoded is! Map<String, dynamic>) return null;
    final result = LrclibResult.fromJson(decoded);
    return result.isUsable ? result : null;
  }

  Future<List<LrclibResult>> _searchDirect(Map<String, String> params) async {
    final decoded = await _getJson('/api/search', params);
    if (decoded is! List) return const [];

    final results = <LrclibResult>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final result = LrclibResult.fromJson(entry);
      if (result.isUsable) results.add(result);
    }
    return results;
  }

  Future<Object?> _getJson(String path, Map<String, String> params) async {
    final client = HttpClient();
    try {
      final uri = Uri.https(_host, path, params);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        await _resolveUserAgent(),
      );

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } on SocketException catch (_) {
      return null;
    } on TimeoutException catch (_) {
      return null;
    } on HttpException catch (_) {
      return null;
    } on FormatException catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _resolveUserAgent() async {
    final cached = _userAgent;
    if (cached != null) return cached;

    var version = 'dev';
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
    } on Object catch (_) {}

    return _userAgent = 'Wispie/$version (https://github.com/sillygru/wispie)';
  }
}

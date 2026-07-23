import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../domain/models/lrclib_result.dart';
import '../domain/services/lrclib_match.dart';
import '../domain/services/lrclib_query.dart';
import '../models/song.dart';

/// Read-only client for the LRCLIB lyrics database (<https://lrclib.net>).
///
/// The service is open — no key, no registration, no documented rate limit —
/// but it asks callers to identify themselves through the User-Agent, so that
/// header is never left at the default.
///
/// Follows the same shape as [UpdateService]: `dart:io` rather than a new
/// package dependency, a short timeout, and every failure surfacing as an empty
/// result rather than an exception, because a lyrics lookup failing is not
/// worth interrupting anything else the user is doing.
class LrclibService {
  static const String _host = 'lrclib.net';
  static const Duration _timeout = Duration(seconds: 8);

  /// Cached so a search does not pay for a platform channel round trip per
  /// request just to build a header.
  static String? _userAgent;

  /// The scanner's stand-in tags for untagged files. LRCLIB treats every query
  /// field as an AND filter, so sending one of these as `artist_name` matches
  /// nothing — see [cleanTag].
  static const _placeholderTags = {
    'unknown title',
    'unknown artist',
    'unknown album',
  };

  /// Trims a tag and drops the scanner's placeholder values, so an untagged
  /// file never turns into an AND filter that LRCLIB cannot satisfy. Returns
  /// null when there is nothing usable to search on.
  static String? cleanTag(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || _placeholderTags.contains(v.toLowerCase())) return null;
    return v;
  }

  /// Looks up lyrics for [song] and returns candidates best-first.
  ///
  /// Runs the exact-match and search endpoints together: `/api/get` needs every
  /// tag to line up with LRCLIB's copy and misses often, while `/api/search` is
  /// forgiving but returns a wide spread. Taking both and ranking the union
  /// gives the precise hit top billing when it exists without leaving the user
  /// empty-handed when it does not.
  Future<List<LrclibResult>> findFor(
    Song song, {
    String? titleOverride,
    String? artistOverride,
  }) async {
    final artist = cleanTag(artistOverride ?? song.artist) ?? '';
    final album = cleanTag(song.album);
    // Local files ripped from video sites carry titles like
    // "Artist - Title (Official Audio)"; strip that noise so it can match
    // LRCLIB's clean track_name.
    final rawTitle = cleanTag(titleOverride ?? song.title) ?? '';
    final title = cleanSearchTitle(rawTitle, artist: artist);
    if (title.isEmpty && artist.isEmpty) return const [];

    final results = await Future.wait([
      getExact(
        trackName: title,
        artistName: artist,
        albumName: album,
        duration: song.duration,
      ),
      search(trackName: title, artistName: artist),
    ]);

    final exact = results[0] as LrclibResult?;
    var found = results[1] as List<LrclibResult>;

    // Structured search needs track_name to match reasonably closely. Free-text
    // is the fallback for the "Artist - Title.mp3" style tags that a local
    // library is full of. Build it from the cleaned parts so a placeholder tag
    // can't leak back into the query.
    if (found.isEmpty) {
      found = await searchFreeText(
          [title, artist].where((s) => s.isNotEmpty).join(' '));
    }

    final merged = <int, LrclibResult>{};
    if (exact != null) merged[exact.id] = exact;
    for (final result in found) {
      merged.putIfAbsent(result.id, () => result);
    }

    return rankLrclibResults(merged.values.toList(), song);
  }

  /// `/api/get` — the exact-match endpoint. Returns null on a 404
  /// (`TrackNotFound`), which is the normal outcome rather than an error.
  Future<LrclibResult?> getExact({
    required String trackName,
    required String artistName,
    String? albumName,
    Duration? duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    final decoded = await _getJson('/api/get', {
      'track_name': trackName,
      'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      // The API takes whole seconds here, not milliseconds.
      if (duration != null) 'duration': '${duration.inSeconds}',
    });

    if (decoded is! Map<String, dynamic>) return null;
    return LrclibResult.fromJson(decoded);
  }

  /// `/api/search` with structured fields.
  Future<List<LrclibResult>> search({
    required String trackName,
    String? artistName,
    String? albumName,
  }) async {
    if (trackName.isEmpty) return const [];

    return _searchWith({
      'track_name': trackName,
      if (artistName != null && artistName.isNotEmpty)
        'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
    });
  }

  /// `/api/search` with a single free-text query.
  Future<List<LrclibResult>> searchFreeText(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    return _searchWith({'q': trimmed});
  }

  Future<List<LrclibResult>> _searchWith(Map<String, String> params) async {
    final decoded = await _getJson('/api/search', params);
    if (decoded is! List) return const [];

    return [
      for (final entry in decoded)
        if (entry is Map<String, dynamic>) LrclibResult.fromJson(entry),
    ];
  }

  Future<Object?> _getJson(String path, Map<String, String> params) async {
    final client = HttpClient();
    try {
      final uri = Uri.https(_host, path, params);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.userAgentHeader, await _resolveUserAgent());

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        // Drain so the connection can be reused/closed cleanly.
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } catch (_) {
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
    } catch (_) {
      // Keep the placeholder — an unidentified request is worse than an
      // imprecise version.
    }

    return _userAgent = 'Wispie/$version (https://github.com/sillygru/wispie)';
  }
}

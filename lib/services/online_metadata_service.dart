import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../domain/models/online_search_result.dart';
import '../models/song.dart';
import 'scanner_service.dart';

/// Client for Deezer & iTunes keyless search APIs.
///
/// Deezer API: ~50 requests per 5s.
/// iTunes API: ~20 requests per minute (soft-cap).
class OnlineMetadataService {
  static final OnlineMetadataService instance =
      OnlineMetadataService._internal();

  OnlineMetadataService._internal();

  factory OnlineMetadataService() => instance;

  static const String _deezerHost = 'api.deezer.com';
  static const String _itunesHost = 'itunes.apple.com';
  static const String _lastfmHost = 'www.last.fm';
  static const Duration _timeout = Duration(seconds: 8);

  static String? _userAgent;

  // Rate limiter for iTunes API: track last request time to enforce 3-second spacing in batch mode
  DateTime? _lastITunesRequest;

  // Rate limiter for Last.fm scraping
  DateTime? _lastLastfmRequest;
  static const Duration _lastfmMinInterval = Duration(seconds: 1);

  // Last.fm HTML scraping regexes (artist/album avatar images)
  static final _lastfmAnyImageRegex = RegExp(
    r'src\=\"(https:\/\/[^\"]*?lastfm[^\"]*?fastly[^\"]*?avatar[^\"]*?\/([a-f0-9]+))\"',
  );
  static final _lastfmOgImageRegex = RegExp(
    r'<meta\s+property="og:image"\s+content="([^"]+)"',
  );
  static final _lastfmGifImageRegex = RegExp(
    '${_lastfmAnyImageRegex.pattern}(?=[^>]*?alt="gif")',
  );

  static final Set<String> _lastfmDummyHashes = {
    '2a96cbd8b46e442fc41c2b86b821562f',
    'c6f59c1e5e7240a4c0d427abd71f3dbb',
  };

  static final List<RegExp> _lastfmRegexes = [
    _lastfmGifImageRegex,
    _lastfmOgImageRegex,
    _lastfmAnyImageRegex,
  ];

  static String? cleanTag(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower == 'unknown title' ||
        lower == 'unknown artist' ||
        lower == 'unknown album' ||
        lower == 'unknown') {
      return null;
    }
    return v;
  }

  /// Cleans titles of extra noise such as "(Official Video)", "ft. Artist", etc.
  static String cleanSearchTitle(String rawTitle, {String? artist}) {
    var title = rawTitle.trim();
    if (title.isEmpty) return '';

    // Remove file extensions if present
    final ext = p.extension(title).toLowerCase();
    final validAudioExts = {
      '.mp3',
      '.m4a',
      '.flac',
      '.wav',
      '.aac',
      '.ogg',
      '.opus',
      '.wma',
      '.alac',
      '.aiff'
    };
    if (validAudioExts.contains(ext)) {
      title = p.basenameWithoutExtension(title);
    }

    // Strip common YouTube/video tag patterns
    title = title.replaceAll(
        RegExp(
            r'\([^)]*(official|lyric|music|video|audio|visualizer|hd|4k)[^)]*\)',
            caseSensitive: false),
        '');
    title = title.replaceAll(
        RegExp(
            r'\[[^\]]*(official|lyric|music|video|audio|visualizer|hd|4k)[^\]]*\]',
            caseSensitive: false),
        '');

    // Strip leading "Artist - " if present
    if (artist != null &&
        artist.isNotEmpty &&
        title.toLowerCase().startsWith('${artist.toLowerCase()} - ')) {
      title = title.substring(artist.length + 3).trim();
    } else if (title.contains(' - ')) {
      // Common format "Artist - Title"
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    // Strip featured artist markers from title
    title = title.replaceAll(
        RegExp(r'\b(ft|feat|featuring)[\.\s].*', caseSensitive: false), '');

    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Searches both Deezer and iTunes in parallel for [song] or custom query.
  Future<List<OnlineSearchResult>> searchParallelForSong(
    Song song, {
    String? queryOverride,
    String? titleOverride,
    String? artistOverride,
  }) async {
    final rawArtist = cleanTag(artistOverride ?? song.artist) ?? '';
    final rawTitle = cleanTag(titleOverride ?? song.title) ??
        p.basenameWithoutExtension(song.filename);
    final cleanTitle = cleanSearchTitle(rawTitle, artist: rawArtist);

    final query = queryOverride ??
        (rawArtist.isNotEmpty ? '$rawArtist $cleanTitle' : cleanTitle);

    if (query.trim().isEmpty) return const [];

    final results = await Future.wait([
      searchDeezerTrack(query),
      searchITunesTrack(query),
    ]);

    final deezerHits = results[0];
    final iTunesHits = results[1];

    final combined = <OnlineSearchResult>[];
    final seenKeys = <String>{};

    void addUnique(OnlineSearchResult res) {
      final key = '${res.title.toLowerCase()}|${res.artist.toLowerCase()}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        combined.add(res);
      }
    }

    // Interleave iTunes (first) and Deezer results, prioritizing iTunes for higher-res artwork
    final maxLen = iTunesHits.length > deezerHits.length
        ? iTunesHits.length
        : deezerHits.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < iTunesHits.length) addUnique(iTunesHits[i]);
      if (i < deezerHits.length) addUnique(deezerHits[i]);
    }

    return combined;
  }

  /// Search Deezer for track
  Future<List<OnlineSearchResult>> searchDeezerTrack(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final decoded = await _getJson(_deezerHost, '/search', {'q': trimmed});
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      return const [];
    }

    final results = <OnlineSearchResult>[];
    for (final item in decoded['data'] as List) {
      if (item is! Map<String, dynamic>) continue;
      final title =
          item['title'] as String? ?? item['title_short'] as String? ?? '';
      final artistMap = item['artist'] as Map<String, dynamic>?;
      final albumMap = item['album'] as Map<String, dynamic>?;

      final artist = artistMap?['name'] as String? ?? '';
      final album = albumMap?['title'] as String? ?? '';
      final coverUrl = albumMap?['cover_xl'] as String? ??
          albumMap?['cover_big'] as String? ??
          albumMap?['cover_medium'] as String?;

      final durationSec = item['duration'] as int?;

      if (title.isNotEmpty) {
        results.add(OnlineSearchResult(
          title: title,
          artist: artist,
          album: album,
          coverUrl: coverUrl,
          source: 'deezer',
          duration: durationSec != null ? Duration(seconds: durationSec) : null,
        ));
      }
    }
    return results;
  }

  /// Search Deezer for artist image
  Future<String?> searchDeezerArtistImage(String artistName) async {
    final clean = cleanTag(artistName);
    if (clean == null) return null;

    final decoded = await _getJson(_deezerHost, '/search/artist', {'q': clean});
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      return null;
    }

    final list = decoded['data'] as List;
    if (list.isEmpty) return null;

    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final picture = item['picture_xl'] as String? ??
            item['picture_big'] as String? ??
            item['picture_medium'] as String?;
        if (picture != null && picture.isNotEmpty) return picture;
      }
    }
    return null;
  }

  /// Search Deezer for album image
  Future<String?> searchDeezerAlbumImage(String albumName,
      {String? artistName}) async {
    final cleanAlbum = cleanTag(albumName);
    if (cleanAlbum == null) return null;
    final cleanArtist = cleanTag(artistName);

    final query = cleanArtist != null ? '$cleanArtist $cleanAlbum' : cleanAlbum;
    final decoded = await _getJson(_deezerHost, '/search/album', {'q': query});
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      return null;
    }

    final list = decoded['data'] as List;
    if (list.isEmpty) return null;

    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cover = item['cover_xl'] as String? ??
            item['cover_big'] as String? ??
            item['cover_medium'] as String?;
        if (cover != null && cover.isNotEmpty) return cover;
      }
    }
    return null;
  }

  /// Search iTunes for track (with rate-limiting pause)
  Future<List<OnlineSearchResult>> searchITunesTrack(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    await _enforceITunesRateLimit();

    final decoded = await _getJson(_itunesHost, '/search', {
      'term': trimmed,
      'entity': 'song',
      'limit': '10',
    });

    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      return const [];
    }

    final results = <OnlineSearchResult>[];
    for (final item in decoded['results'] as List) {
      if (item is! Map<String, dynamic>) continue;
      final title = item['trackName'] as String? ?? '';
      final artist = item['artistName'] as String? ?? '';
      final album = item['collectionName'] as String? ?? '';
      var artwork = item['artworkUrl100'] as String?;

      if (artwork != null && artwork.isNotEmpty) {
        artwork = _upgradeITunesArtworkUrl(artwork);
      }

      final millis = item['trackTimeMillis'] as int?;

      if (title.isNotEmpty) {
        results.add(OnlineSearchResult(
          title: title,
          artist: artist,
          album: album,
          coverUrl: artwork,
          source: 'itunes',
          duration: millis != null ? Duration(milliseconds: millis) : null,
        ));
      }
    }
    return results;
  }

  /// Search iTunes for artist image (fetches top album or artist entity artwork)
  Future<String?> searchITunesArtistImage(String artistName) async {
    final clean = cleanTag(artistName);
    if (clean == null) return null;

    await _enforceITunesRateLimit();

    final decoded = await _getJson(_itunesHost, '/search', {
      'term': clean,
      'entity': 'album',
      'limit': '5',
    });

    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      return null;
    }

    final list = decoded['results'] as List;
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final artwork = item['artworkUrl100'] as String?;
        if (artwork != null && artwork.isNotEmpty) {
          return _upgradeITunesArtworkUrl(artwork);
        }
      }
    }
    return null;
  }

  /// Search iTunes for album image
  Future<String?> searchITunesAlbumImage(String albumName,
      {String? artistName}) async {
    final cleanAlbum = cleanTag(albumName);
    if (cleanAlbum == null) return null;
    final cleanArtist = cleanTag(artistName);

    await _enforceITunesRateLimit();

    final query = cleanArtist != null ? '$cleanArtist $cleanAlbum' : cleanAlbum;
    final decoded = await _getJson(_itunesHost, '/search', {
      'term': query,
      'entity': 'album',
      'limit': '5',
    });

    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      return null;
    }

    final list = decoded['results'] as List;
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final artwork = item['artworkUrl100'] as String?;
        if (artwork != null && artwork.isNotEmpty) {
          return _upgradeITunesArtworkUrl(artwork);
        }
      }
    }
    return null;
  }

  /// Searches Last.fm by scraping HTML for an artist avatar image.
  Future<String?> searchLastfmArtistImage(String artistName) async {
    final clean = cleanTag(artistName);
    if (clean == null) return null;
    final encoded = Uri.encodeComponent(clean);
    return _searchLastfmPage('/music/$encoded/+images');
  }

  /// Searches Last.fm by scraping HTML for an album cover image.
  Future<String?> searchLastfmAlbumImage(String albumName,
      {String? artistName}) async {
    final cleanAlbum = cleanTag(albumName);
    if (cleanAlbum == null) return null;
    final cleanArtist = cleanTag(artistName);
    if (cleanArtist == null) return null;
    final encodedAlbum = Uri.encodeComponent(cleanAlbum);
    final encodedArtist = Uri.encodeComponent(cleanArtist);
    return _searchLastfmPage('/music/$encodedArtist/$encodedAlbum/+images');
  }

  /// Fetches a Last.fm page and extracts the best image URL from its HTML.
  /// Tries GIF image, then og:image meta tag, then any avatar image.
  Future<String?> _searchLastfmPage(String path) async {
    final now = DateTime.now();
    if (_lastLastfmRequest != null) {
      final elapsed = now.difference(_lastLastfmRequest!);
      if (elapsed < _lastfmMinInterval) {
        await Future.delayed(_lastfmMinInterval - elapsed);
      }
    }
    _lastLastfmRequest = DateTime.now();

    final client = HttpClient();
    try {
      final uri = Uri.https(_lastfmHost, path);
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.userAgentHeader, await _resolveUserAgent());

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final html = await response.transform(utf8.decoder).join();
      return _extractLastfmImageUrl(html);
    } catch (e) {
      debugPrint('Last.fm scrape error for $path: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Runs the ordered regexes against [html] and validates the result.
  String? _extractLastfmImageUrl(String html) {
    for (final regex in _lastfmRegexes) {
      final match = regex.firstMatch(html);
      if (match == null) continue;
      final url = match.group(1);
      if (url == null || url.isEmpty) continue;

      final isDummy =
          _lastfmDummyHashes.any((hash) => url.endsWith('$hash.jpg'));
      if (!isDummy) return url;
    }
    return null;
  }

  /// Upgrades iTunes 100x100 artwork URL to 600x600 or 1000x1000
  String _upgradeITunesArtworkUrl(String url) {
    return url
        .replaceAll('100x100bb', '600x600bb')
        .replaceAll('100x100', '600x600');
  }

  Future<void> _enforceITunesRateLimit() async {
    final now = DateTime.now();
    if (_lastITunesRequest != null) {
      final elapsed = now.difference(_lastITunesRequest!);
      if (elapsed < const Duration(seconds: 2)) {
        await Future.delayed(const Duration(seconds: 2) - elapsed);
      }
    }
    _lastITunesRequest = DateTime.now();
  }

  /// Downloads cover art from [imageUrl] and saves it locally in extracted covers directory.
  Future<String?> downloadAndCacheCover(String imageUrl, String keyName) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(imageUrl);
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.userAgentHeader, await _resolveUserAgent());

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final bytesBuilder = BytesBuilder();
      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }
      final bytes = bytesBuilder.takeBytes();
      if (bytes.isEmpty) return null;

      final coversDir = await ScannerService.coversDirectory();
      final sanitizedKey = keyName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName =
          'online_${sanitizedKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(p.join(coversDir.path, fileName));
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      debugPrint('Error downloading cover from $imageUrl: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _getJson(
      String host, String path, Map<String, String> params) async {
    final client = HttpClient();
    try {
      final uri = Uri.https(host, path, params);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.userAgentHeader, await _resolveUserAgent());

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } catch (e) {
      debugPrint('OnlineMetadataService GET $path error: $e');
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
    } catch (_) {}

    return _userAgent = 'Wispie/$version (https://github.com/sillygru/wispie)';
  }
}

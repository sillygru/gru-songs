import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/song.dart';
import 'database_service.dart';

class ApiService {
  static String _baseUrl = "";

  static String get baseUrl => _baseUrl;

  static void setBaseUrl(String url) {
    _baseUrl = url;
  }

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? createClient();

  http.Client get client => _client;

  static http.Client createClient() {
    final HttpClient ioc = HttpClient();
    ioc.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    ioc.connectionTimeout = const Duration(seconds: 30);
    return IOClient(ioc);
  }

  String? _username;
  void setUsername(String? username) => _username = username;

  Map<String, dynamic>? _funStatsCache;
  DateTime? _lastFunStatsFetch;
  String? _lastCachedUsername;

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
        'Accept': 'application/json',
        if (_username != null) 'x-username': _username!,
        'Content-Type': 'application/json',
      };

  Future<List<Song>> fetchSongs() async {
    // This is now legacy but keeping for reference if needed elsewhere
    // In the new architecture, we scan locally.
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/list-songs'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Song.fromJson(item)).toList();
      } else {
        throw Exception(
            'Failed to load songs (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadSong(File file, String? filename) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/music/upload'));
      request.headers.addAll(_headers);
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      if (filename != null && filename.isNotEmpty) {
        request.fields['filename'] = filename;
      }

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> fetchLyrics(String url) async {
    try {
      final response = await _client.get(
        Uri.parse(getFullUrl(url)),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getFunStats() async {
    // 1. Check RAM Cache (5 minute TTL, also per-user)
    if (_funStatsCache != null &&
        _lastFunStatsFetch != null &&
        _lastCachedUsername == _username) {
      final diff = DateTime.now().difference(_lastFunStatsFetch!);
      if (diff.inMinutes < 5) {
        return _funStatsCache!;
      }
    }

    // 2. Local Calculation (Always used for speed and offline support)
    // Since stats DB is synced bidirectionally, local calculation provides the same data as the server.
    final localStats = await DatabaseService.instance.getFunStats();
    _funStatsCache = localStats;
    _lastFunStatsFetch = DateTime.now();
    _lastCachedUsername = _username;
    return localStats;
  }

  Future<void> renameFile(String oldFilename, String newName, int deviceCount,
      {String type = "file", String? artist, String? album}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/user/rename-file'),
        headers: _headers,
        body: jsonEncode({
          'old_filename': oldFilename,
          'new_name': newName,
          'type': type,
          'device_count': deviceCount,
          if (artist != null) 'artist': artist,
          if (album != null) 'album': album,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Rename failed: ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getPendingRenames() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/user/pending-renames'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get pending renames');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> acknowledgeRename(String oldFilename, String newName,
      {String type = "file", String? artist, String? album}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/user/acknowledge-rename'),
        headers: _headers,
        body: jsonEncode({
          'old_filename': oldFilename,
          'new_name': newName,
          'type': type,
          if (artist != null) 'artist': artist,
          if (album != null) 'album': album,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Acknowledge rename failed: ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  String getFullUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final cleanRelative =
        relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';
    return '$baseUrl$cleanRelative';
  }

  void dispose() {
    _client.close();
  }
}

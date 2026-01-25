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
    ioc.connectionTimeout = const Duration(seconds: 15); // Reduced from 30
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
        'Connection': 'keep-alive', // Enable connection pooling
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
    // 1. Check RAM Cache (3 minute TTL, also per-user) - Reduced from 5 minutes
    if (_funStatsCache != null &&
        _lastFunStatsFetch != null &&
        _lastCachedUsername == _username) {
      final diff = DateTime.now().difference(_lastFunStatsFetch!);
      if (diff.inMinutes < 3) {
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

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/song.dart';

class ApiService {
  static const String baseUrl = 'https://[REDACTED]/music';
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

  Future<http.Response> downloadYoutube(
      String url, String title) async {
    try {
      // Send as form data because FastAPI uses Form(...)
      final response = await _client.post(
        Uri.parse('$baseUrl/music/yt-dlp'),
        headers: {
          ..._headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'url': url,
          'title': title,
        },
      );

      return response;
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
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/stats/fun'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load fun stats');
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

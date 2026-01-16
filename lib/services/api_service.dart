import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/song.dart';

class ApiService {
  static const String baseUrl = 'https://[REDACTED]/music';
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? createClient();

  static http.Client createClient() {
    final HttpClient ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    ioc.connectionTimeout = const Duration(seconds: 30);
    return IOClient(ioc);
  }

  String? _username;
  void setUsername(String? username) => _username = username;

  Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
    'Accept': 'application/json',
    if (_username != null) 'x-username': _username!,
    'Content-Type': 'application/json',
  };

  Future<List<Song>> fetchSongs() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/list-songs'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Song.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load songs (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, String>> fetchSyncHashes() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/sync-check'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return Map<String, String>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to fetch sync hashes (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadSong(File file, String? filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/music/upload'));
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
        throw Exception('Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> downloadYoutube(String url, String? filename) async {
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
          if (filename != null && filename.isNotEmpty) 'filename': filename,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('YouTube download failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Queue & Sync
  Future<Map<String, dynamic>> fetchQueue() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/queue'), headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to fetch queue: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> syncQueue(List<Map<String, dynamic>> queue, int currentIndex, int version) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/queue/sync'),
        headers: _headers,
        body: jsonEncode({
          'queue': queue,
          'current_index': currentIndex,
          'version': version,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to sync queue: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchNextSong() async {
    try {
      final response = await _client.post(Uri.parse('$baseUrl/queue/next'), headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFunStats() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/stats/fun'), headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to fetch fun stats: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> fetchLyrics(String url) async {
    try {
      final response = await _client.get(Uri.parse(getFullUrl(url)));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String getFullUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final cleanRelative = relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';
    return '$baseUrl$cleanRelative';
  }

  void dispose() {
    _client.close();
  }
}
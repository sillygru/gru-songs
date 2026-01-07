import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/song.dart';

class ApiService {
  static const String baseUrl = 'https://[REDACTED]/music';

  static http.Client getClient() {
    final HttpClient ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    ioc.connectionTimeout = const Duration(seconds: 30);
    return IOClient(ioc);
  }

  Future<List<Song>> fetchSongs() async {
    final client = getClient();
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/list-songs'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Song.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load songs (${response.statusCode}): ${response.body}');
      }
    } finally {
      client.close();
    }
  }

  Future<String?> fetchLyrics(String url) async {
    final client = getClient();
    try {
      final response = await client.get(Uri.parse(getFullUrl(url)));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  static String getFullUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final cleanRelative = relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';
    return '$baseUrl$cleanRelative';
  }
}

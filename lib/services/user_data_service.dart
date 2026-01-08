import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../models/playlist.dart';

class UserDataService {
  final http.Client _client;

  UserDataService(ApiService apiService) : _client = ApiService.createClient();

  Map<String, String> _getHeaders(String username) {
    return {
      'Content-Type': 'application/json',
      'x-username': username,
    };
  }

  // --- Favorites ---

  Future<List<String>> getFavorites(String username) async {
    final response = await _client.get(
      Uri.parse('${ApiService.baseUrl}/user/favorites'),
      headers: _getHeaders(username),
    );

    if (response.statusCode == 200) {
      return List<String>.from(jsonDecode(response.body));
    }
    return [];
  }

  Future<void> addFavorite(String username, String songFilename, String sessionId) async {
    await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/favorites'),
      headers: _getHeaders(username),
      body: jsonEncode({
          'song_filename': songFilename,
          'session_id': sessionId
      }),
    );
  }

  Future<void> removeFavorite(String username, String songFilename) async {
    await _client.delete(
      Uri.parse('${ApiService.baseUrl}/user/favorites/$songFilename'),
      headers: _getHeaders(username),
    );
  }

  // --- Suggest Less ---

  Future<List<String>> getSuggestLess(String username) async {
    final response = await _client.get(
      Uri.parse('${ApiService.baseUrl}/user/suggest-less'),
      headers: _getHeaders(username),
    );

    if (response.statusCode == 200) {
      return List<String>.from(jsonDecode(response.body));
    }
    return [];
  }

  Future<void> addSuggestLess(String username, String songFilename) async {
    await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/suggest-less'),
      headers: _getHeaders(username),
      body: jsonEncode({'song_filename': songFilename}),
    );
  }

  Future<void> removeSuggestLess(String username, String songFilename) async {
    await _client.delete(
      Uri.parse('${ApiService.baseUrl}/user/suggest-less/$songFilename'),
      headers: _getHeaders(username),
    );
  }

  // --- Playlists ---

  Future<List<Playlist>> getPlaylists(String username) async {
    final response = await _client.get(
      Uri.parse('${ApiService.baseUrl}/user/playlists'),
      headers: _getHeaders(username),
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => Playlist.fromJson(e)).toList();
    }
    return [];
  }

  Future<Playlist> createPlaylist(String username, String name) async {
    final response = await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/playlists'),
      headers: _getHeaders(username),
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return Playlist.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create playlist');
    }
  }

  Future<void> deletePlaylist(String username, String playlistId) async {
    await _client.delete(
      Uri.parse('${ApiService.baseUrl}/user/playlists/$playlistId'),
      headers: _getHeaders(username),
    );
  }

  Future<void> addSongToPlaylist(String username, String playlistId, String songFilename) async {
    await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/playlists/$playlistId/songs'),
      headers: _getHeaders(username),
      body: jsonEncode({'song_filename': songFilename}),
    );
  }

  Future<void> removeSongFromPlaylist(String username, String playlistId, String songFilename) async {
    await _client.delete(
      Uri.parse('${ApiService.baseUrl}/user/playlists/$playlistId/songs/$songFilename'),
      headers: _getHeaders(username),
    );
  }
}

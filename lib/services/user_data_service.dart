import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class UserDataService {
  final http.Client _client;

  UserDataService(ApiService apiService) : _client = ApiService.createClient();

  Map<String, String> _getHeaders(String username) {
    return {
      'Content-Type': 'application/json',
      'x-username': username,
    };
  }

  // --- Comprehensive User Data Sync ---

  Future<Map<String, dynamic>> getUserData(String username) async {
    final headers = _getHeaders(username);
    final response = await _client.get(
      Uri.parse('${ApiService.baseUrl}/user/data'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final body = response.body;
      debugPrint('UserDataService: GET /user/data for $username -> $body');
      return jsonDecode(body);
    }
    return {
      'favorites': [],
      'suggestLess': [],
      'shuffleState': {},
    };
  }

  Future<void> updateUserData(String username, Map<String, dynamic> userData) async {
    final body = jsonEncode(userData);
    debugPrint('UserDataService: POST /user/data for $username -> $body');
    await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/data'),
      headers: _getHeaders(username),
      body: body,
    );
  }

  // --- Legacy Individual Methods (for backward compatibility) ---

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

  Future<void> addFavorite(
      String username, String songFilename, String sessionId) async {
    await _client.post(
      Uri.parse('${ApiService.baseUrl}/user/favorites'),
      headers: _getHeaders(username),
      body:
          jsonEncode({'song_filename': songFilename, 'session_id': sessionId}),
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
}

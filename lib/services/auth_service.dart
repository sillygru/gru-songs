import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AuthService {
  final http.Client _client;

  AuthService() : _client = ApiService.createClient();

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('${ApiService.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Login failed');
    }
  }

  Future<void> signup(String username, String password) async {
    final response = await _client.post(
      Uri.parse('${ApiService.baseUrl}/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Signup failed');
    }
  }

  Future<void> updatePassword(
      String username, String oldPassword, String newPassword) async {
    final response = await _client.post(
      Uri.parse('${ApiService.baseUrl}/auth/update-password'),
      headers: {
        'Content-Type': 'application/json',
        'x-username': username,
      },
      body: jsonEncode(
          {'old_password': oldPassword, 'new_password': newPassword}),
    );

    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Update failed');
    }
  }

  Future<String> updateUsername(
      String currentUsername, String newUsername) async {
    final response = await _client.post(
      Uri.parse('${ApiService.baseUrl}/auth/update-username'),
      headers: {
        'Content-Type': 'application/json',
        'x-username': currentUsername,
      },
      body: jsonEncode({'new_username': newUsername}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['username'];
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Update failed');
    }
  }
}

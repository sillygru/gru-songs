class AuthService {
  AuthService();

  Future<String> updateUsername(String newUsername) async {
    // Local-only - just validate inputs
    if (newUsername.isEmpty) {
      throw Exception('Display name cannot be empty');
    }
    return newUsername;
  }
}

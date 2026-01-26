class AuthService {
  AuthService();

  Future<Map<String, dynamic>> login(String username, String password) async {
    // Local-only - just validate inputs
    if (username.isEmpty) {
      throw Exception('Username cannot be empty');
    }
    if (password.isEmpty) {
      throw Exception('Password cannot be empty');
    }
    
    return {'message': 'Login successful', 'username': username};
  }

  Future<void> signup(String username, String password) async {
    // Local-only - just validate inputs
    if (username.isEmpty) {
      throw Exception('Username cannot be empty');
    }
    if (password.isEmpty) {
      throw Exception('Password cannot be empty');
    }
  }

  Future<void> updatePassword(String username, String oldPassword, String newPassword) async {
    // Local-only - just validate inputs
    if (oldPassword.isEmpty || newPassword.isEmpty) {
      throw Exception('Passwords cannot be empty');
    }
  }

  Future<String> updateUsername(String username, String newUsername) async {
    // Local-only - just validate inputs
    if (newUsername.isEmpty) {
      throw Exception('New username cannot be empty');
    }
    return newUsername;
  }
}

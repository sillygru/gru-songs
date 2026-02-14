import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class AuthState {
  final String? username;
  final bool isLoading;
  final String? error;

  AuthState({this.username, this.isLoading = false, this.error});

  bool get isAuthenticated => username != null;

  AuthState copyWith({String? username, bool? isLoading, String? error}) {
    return AuthState(
      username: username ?? this.username,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late final AuthService _authService;

  @override
  AuthState build() {
    _authService = ref.watch(authServiceProvider);
    _loadUser();
    return AuthState();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username != null) {
      state = state.copyWith(username: username);
    }
  }

  Future<void> setDisplayName(String username) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      state = state.copyWith(username: username, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateUsername(String newUsername) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updatedName = await _authService.updateUsername(newUsername);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', updatedName);
      state = state.copyWith(username: updatedName, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }
}

final authServiceProvider = Provider((ref) => AuthService());

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

class PreloadedAuthNotifier extends AuthNotifier {
  final String? initialUsername;

  PreloadedAuthNotifier(this.initialUsername);

  @override
  AuthState build() {
    _authService = ref.watch(authServiceProvider);
    return AuthState(username: initialUsername);
  }
}

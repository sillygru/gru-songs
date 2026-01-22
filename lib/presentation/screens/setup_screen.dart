import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../services/storage_service.dart';
import '../../services/api_service.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  // Step 0: Mode Selection, Step 1: Configuration
  int _currentStep = 0;
  bool _isLocalMode = false;
  bool _isLogin = true;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();

  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.1),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _currentStep == 0
                      ? _buildModeSelection()
                      : _buildConfiguration(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelection() {
    return Column(
      key: const ValueKey('mode_selection'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.music_note_rounded,
            size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Gru Songs',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'High-performance music streaming',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        _buildModeCard(
          title: 'Local Experience',
          description:
              'Keep everything on this device. No server required. Fast and private.',
          icon: Icons.smartphone_rounded,
          isLocal: true,
        ),
        const SizedBox(height: 16),
        _buildModeCard(
          title: 'Sync with Server',
          description: 'Sync stats and favorites with your self-hosted server.',
          icon: Icons.cloud_sync_rounded,
          isLocal: false,
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isLocal,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _isLocalMode = isLocal;
            _currentStep = 1;
          });
        },
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon,
                    size: 32, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfiguration() {
    return Column(
      key: const ValueKey('configuration'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _currentStep = 0),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isLocalMode ? 'Welcome' : 'Server Connection',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (!_isLocalMode) ...[
          _buildTextField(
            controller: _serverUrlController,
            label: 'Server URL',
            hint: 'http://192.168.1.5:9000',
            icon: Icons.dns_rounded,
          ),
          const SizedBox(height: 16),
        ],
        _buildTextField(
          controller: _usernameController,
          label: 'Username',
          icon: Icons.person_rounded,
        ),
        if (!_isLocalMode) ...[
          const SizedBox(height: 16),
          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_rounded,
            obscureText: true,
          ),
        ],
        const SizedBox(height: 40),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                _isLocalMode
                    ? 'Start Listening'
                    : (_isLogin ? 'Connect & Login' : 'Create & Connect'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        if (!_isLocalMode) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _isLogin = !_isLogin;
              });
            },
            child: Text(_isLogin
                ? 'Need an account? Sign up'
                : 'Already have an account? Login'),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a username')),
      );
      return;
    }

    if (!_isLocalMode) {
      final url = _serverUrlController.text.trim();
      final password = _passwordController.text.trim();

      if (url.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields')),
        );
        return;
      }

      setState(() => _isLoading = true);

      // Test URL formatting
      String formattedUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        formattedUrl = 'http://$url';
      }
      if (formattedUrl.endsWith('/')) {
        formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
      }

      try {
        // Set URL
        ApiService.setBaseUrl(formattedUrl);
        await StorageService().setServerUrl(formattedUrl);

        // Attempt Login or Signup
        if (_isLogin) {
          await ref.read(authProvider.notifier).login(username, password);
        } else {
          await ref.read(authProvider.notifier).signup(username, password);
        }

        final authState = ref.read(authProvider);
        if (authState.error != null) {
          throw Exception(authState.error);
        }

        // Save Mode
        await StorageService().setIsLocalMode(false);
        await StorageService().setSetupComplete(true);
        ref.read(setupProvider.notifier).setComplete(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Connection failed: $e'),
                backgroundColor: Colors.red),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    } else {
      setState(() => _isLoading = true);
      // Local Mode
      try {
        // Clear the server URL when switching to local mode
        ApiService.setBaseUrl("");
        await StorageService().setServerUrl("");
        await StorageService().setIsLocalMode(true);
        await StorageService().setLocalUsername(username);
        await StorageService().setSetupComplete(true);

        await ref.read(authProvider.notifier).localLogin(username);
        ref.read(setupProvider.notifier).setComplete(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    }

    // If we're here, we're done (AuthNotifier handles navigation if watching isAuthenticated, or we trigger rebuild)
    // Actually, main.dart checks isAuthenticated.
    // If we completed setup, we need to ensure main.dart rebuilds or we navigate.
    // Since main.dart switches on isAuthenticated vs Setup, let's just wait?
    // main.dart might need a RestartWidget or similar if it depends on async future.
    // But since we are updating Provider state, it should rebuild.

    // However, main.dart's logic for SetupScreen vs MainScreen might be static after FutureBuilder.
    // We will handle this in main.dart next.
  }
}

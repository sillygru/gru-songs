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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _currentStep == 0 ? _buildModeSelection() : _buildConfiguration(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome to Gru Songs',
          style: Theme.of(context).textTheme.headlineLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Choose how you want to use the app',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        _buildModeCard(
          title: 'Local Only',
          description: 'Keep everything on this device. No server required. No sync.',
          icon: Icons.smartphone,
          isLocal: true,
        ),
        const SizedBox(height: 16),
        _buildModeCard(
          title: 'Sync with Server',
          description: 'Sync stats and favorites with a self-hosted server.',
          icon: Icons.cloud_sync,
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _isLocalMode = isLocal;
            _currentStep = 1;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfiguration() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                });
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isLocalMode ? 'Local Setup' : 'Server Setup',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (!_isLocalMode) ...[
            Text(
              'Enter your server address (e.g., http://192.168.1.5:9000)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
             const SizedBox(height: 8),
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          if (!_isLocalMode) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
          ],
          const SizedBox(height: 32),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(
              onPressed: _submit,
              child: Text(_isLocalMode
                  ? 'Start Using App'
                  : (_isLogin ? 'Connect & Login' : 'Connect & Sign Up')),
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
                    : 'Have an account? Login'),
              ),
            ],
        ],
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
            SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
      
    } else {
      setState(() => _isLoading = true);
      // Local Mode
      try {
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

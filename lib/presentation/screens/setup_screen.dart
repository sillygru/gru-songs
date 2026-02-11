import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/storage_service.dart';
import '../../services/telemetry_service.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _showTelemetry = false;

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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Logo/Title
                    Icon(
                      Icons.music_note_rounded,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Wispie',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your personal music library',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    if (!_showTelemetry) ...[
                      // Username Input
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'Enter your username',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_isLoading,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleLogin(),
                      ),
                      const SizedBox(height: 24),

                      // Login Button
                      FilledButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Start Listening',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ] else ...[
                      // Telemetry Section
                      Text(
                        'Share anonymous data with developers?',
                        style: Theme.of(context).textTheme.titleSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Consumer(builder: (context, ref, child) {
                        final settings = ref.watch(settingsProvider);
                        final levels = ['Level 0', 'Level 1', 'Level 2'];
                        return Column(
                          children: [
                            Slider(
                              value: settings.telemetryLevel
                                  .toDouble()
                                  .clamp(0, 2),
                              min: 0,
                              max: 2,
                              divisions: 2,
                              label:
                                  levels[settings.telemetryLevel.clamp(0, 2)],
                              onChanged: (val) {
                                ref
                                    .read(settingsProvider.notifier)
                                    .setTelemetryLevel(val.toInt());
                              },
                            ),
                            Text(
                              levels[settings.telemetryLevel.clamp(0, 2)],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Level explanation info
                            _buildLevelExplanation(
                                settings.telemetryLevel.clamp(0, 2)),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),

                      // Complete Button
                      FilledButton(
                        onPressed: _isLoading ? null : _handleComplete,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Complete Setup',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelExplanation(int level) {
    final explanations = [
      '• No data will be shared with developers.',
      '• Basic app information (version, platform).\n• App startup notification.',
      '• Everything in level 1.\n• Anonymous usage events (settings changed).\n• Library rescans and data management (import/export).',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        explanations[level],
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a username'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _showTelemetry = true);
  }

  Future<void> _handleComplete() async {
    final username = _usernameController.text.trim();
    setState(() => _isLoading = true);

    try {
      // Set up local mode
      final storage = StorageService();
      await storage.setIsLocalMode(true);
      await storage.setLocalUsername(username);
      await storage.setSetupComplete(true);

      // Log in as local user
      await ref.read(authProvider.notifier).localLogin(username);

      // Track first startup (always sent regardless of level)
      final settings = ref.read(settingsProvider);
      await TelemetryService.instance
          .trackFirstStartup(settings.telemetryLevel);

      // Update setup provider to trigger UI rebuild
      ref.read(setupProvider.notifier).setComplete(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Setup failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/storage_service.dart';
import '../../services/telemetry_service.dart';

enum _SetupStep { username, telemetry, permissions }

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _usernameController = TextEditingController();
  _SetupStep _currentStep = _SetupStep.username;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _folderSelected = false;
  bool _permissionDeniedOnce = false;

  bool get _showAndroidPermissionStep =>
      Platform.isAndroid && _currentStep == _SetupStep.permissions;

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

                    if (_currentStep == _SetupStep.username) ...[
                      _buildUsernameStep(),
                    ] else if (_currentStep == _SetupStep.telemetry) ...[
                      _buildTelemetryStep(),
                    ] else if (_showAndroidPermissionStep) ...[
                      _buildPermissionStep(),
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

  Widget _buildUsernameStep() {
    return Column(
      children: [
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'What should we call you?',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          enabled: !_isLoading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _handleLogin,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildTelemetryStep() {
    return Column(
      children: [
        Text(
          'Share anonymous data with developers?',
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Consumer(builder: (context, ref, child) {
          final settings = ref.watch(settingsProvider);
          const levels = ['Level 0', 'Level 1', 'Level 2', 'Level 3'];
          return Column(
            children: [
              Slider(
                value: settings.telemetryLevel.toDouble().clamp(0, 3),
                min: 0,
                max: 3,
                divisions: 3,
                label: levels[settings.telemetryLevel.clamp(0, 3)],
                onChanged: (val) {
                  ref
                      .read(settingsProvider.notifier)
                      .setTelemetryLevel(val.toInt());
                },
              ),
              Text(
                levels[settings.telemetryLevel.clamp(0, 3)],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              _buildLevelExplanation(settings.telemetryLevel.clamp(0, 3)),
            ],
          );
        }),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _handleComplete,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Complete Setup', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildPermissionStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.storage_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Storage Access Needed',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'To browse and play your music, Wispie needs permission to '
                'access files on your device. Your music stays local and is '
                'never shared.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              if (!_permissionGranted) ...[
                FilledButton.icon(
                  onPressed: _isLoading ? null : _requestPermission,
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: Text(_permissionDeniedOnce
                      ? 'Open App Settings'
                      : 'Grant Storage Access'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                  ),
                ),
                if (_permissionDeniedOnce) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Permission was permanently denied. Please grant storage '
                    'access in system settings.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.8),
                        ),
                  ),
                ],
              ] else ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Storage access granted',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickMusicFolder,
                  icon: Icon(
                    _folderSelected
                        ? Icons.check_circle_outline
                        : Icons.add_rounded,
                    size: 20,
                    color: _folderSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  label: Text(
                    _folderSelected
                        ? 'Music folder selected'
                        : 'Select Music Folder',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _finishSetup,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Finish Setup', style: TextStyle(fontSize: 16)),
        ),
        if (!_permissionGranted) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : _finishSetup,
            child: const Text('Skip for now'),
          ),
        ],
      ],
    );
  }

  Widget _buildLevelExplanation(int level) {
    final explanations = [
      'No data will be shared with developers.',
      'Basic app information (version, platform).\nApp startup notification.',
      'Everything in level 1.\nAnonymous usage events (settings changed).\nLibrary rescans and data management (import/export).',
      'Everything in level 2.\nUsage data: how often and how long you use the app.\nWeekly listening statistics (hours played).',
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

    setState(() => _currentStep = _SetupStep.telemetry);
  }

  Future<void> _handleComplete() async {
    final username = _usernameController.text.trim();
    setState(() => _isLoading = true);

    try {
      // Persist setup data
      final storage = StorageService();
      await storage.setIsLocalMode(true);
      await storage.setSetupComplete(true);

      // Set display name
      await ref.read(authProvider.notifier).setDisplayName(username);

      // Track first startup (always sent regardless of level)
      final settings = ref.read(settingsProvider);
      await TelemetryService.instance
          .trackFirstStartup(settings.telemetryLevel);

      // On Android, move to permission step before navigating to main screen
      if (Platform.isAndroid && mounted) {
        setState(() {
          _currentStep = _SetupStep.permissions;
          _isLoading = false;
        });
      } else {
        // Update setup provider to trigger UI rebuild
        ref.read(setupProvider.notifier).setComplete(true);
      }
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

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      setState(() => _isLoading = true);

      // Check current status first
      var status = await Permission.manageExternalStorage.status;

      if (status.isGranted) {
        setState(() {
          _permissionGranted = true;
          _isLoading = false;
        });
        return;
      }

      // Check if permanently denied
      if (status.isPermanentlyDenied) {
        setState(() {
          _permissionDeniedOnce = true;
          _isLoading = false;
        });
        await openAppSettings();
        // Re-check after returning from settings
        status = await Permission.manageExternalStorage.status;
        if (status.isGranted && mounted) {
          setState(() => _permissionGranted = true);
        }
        return;
      }

      // Request permission
      status = await Permission.manageExternalStorage.request();

      if (status.isGranted) {
        if (mounted) {
          setState(() => _permissionGranted = true);
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() => _permissionDeniedOnce = true);
        }
      } else {
        // Denied (not permanent) - show message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Storage permission is needed to access your music files. '
                'You can enable it later in Settings.',
              ),
            ),
          );
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickMusicFolder() async {
    final storage = StorageService();
    final selection = await storage.pickMusicFolder();
    if (selection == null || selection['path']!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to access selected folder'),
          ),
        );
      }
      return;
    }

    await storage.addMusicFolder(
      selection['path']!,
      selection['treeUri'],
      iosBookmarkId: selection['iosBookmarkId'],
      platform: selection['platform'],
    );

    if (mounted) {
      setState(() => _folderSelected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Music folder added')),
      );
    }
  }

  void _finishSetup() {
    ref.read(setupProvider.notifier).setComplete(true);
    // The provider change triggers a UI rebuild to MainScreen.
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }
}

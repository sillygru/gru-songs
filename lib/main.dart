import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:metadata_god/metadata_god.dart';
import 'dart:async';
import 'dart:io';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/setup_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/cache_service.dart';
import 'services/storage_service.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallel initialization
  await Future.wait([
    _initializeMetadataGod(),
    CacheService.instance.init(),
    _setupAudioSession(),
    _setupJustAudioBackground(),
  ], eagerError: false);

  PaintingBinding.instance.imageCache.maximumSize = 250;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;

  final storage = StorageService();
  bool isSetupComplete = await storage.getIsSetupComplete();

  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString('username');

  // Single user mode: always init database
  final migrated = await DatabaseService.instance.init();

  if (migrated) {
    debugPrint("Data migrated to single-user format. Restarting app...");
    // Direct exit to force restart/relaunch with new state
    exit(0);
  }

  // Set local mode by default
  await storage.setIsLocalMode(true);

  if (!isSetupComplete) {
    // If setup not complete, we might need migration check or fresh start
  }

  runApp(ProviderScope(
    overrides: [
      setupProvider
          .overrideWith(() => InitializedSetupNotifier(isSetupComplete)),
      authProvider.overrideWith(() => PreloadedAuthNotifier(username)),
    ],
    child: const WispieApp(),
  ));
}

Future<void> _initializeMetadataGod() async {
  try {
    await MetadataGod.initialize();
  } catch (e) {
    debugPrint("Failed to initialize MetadataGod: $e");
  }
}

Future<void> _setupAudioSession() async {
  await AudioSession.instance.then(
      (session) => session.configure(const AudioSessionConfiguration.music()));
}

Future<void> _setupJustAudioBackground() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sillygru.gru_songs.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: false,
  );
}

class InitializedSetupNotifier extends SetupNotifier {
  final bool initialValue;
  InitializedSetupNotifier(this.initialValue);
  @override
  bool build() => initialValue;
}

class WispieApp extends ConsumerWidget {
  const WispieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isSetupComplete = ref.watch(setupProvider);
    final themeState = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Wispie',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(themeState),
      home: AnimatedTheme(
        data: AppTheme.getTheme(themeState),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        child: (!isSetupComplete || !authState.isAuthenticated)
            ? const SetupScreen()
            : const MainScreen(),
      ),
    );
  }
}

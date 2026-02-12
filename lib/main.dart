import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:metadata_god/metadata_god.dart';
import 'dart:async';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'providers/auth_provider.dart';
import 'services/cache_service.dart';
import 'services/storage_service.dart';
import 'services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/setup_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run initialization in parallel for faster startup
  await Future.wait([
    // Initialize MetadataGod early to prevent flutter_rust_bridge initialization errors
    _initializeMetadataGod(),
    // Initialize Cache V3 and cleanup legacy caches
    CacheService.instance.init(),
    // Setup audio session
    _setupAudioSession(),
    // Setup JustAudioBackground
    _setupJustAudioBackground(),
  ], eagerError: false);

  // Limit image cache to save RAM
  PaintingBinding.instance.imageCache.maximumSize =
      250; // Increased count for thumbnails
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      40 * 1024 * 1024; // Balanced 40MB limit

  // Check setup status
  final storage = StorageService();
  bool isSetupComplete = await storage.getIsSetupComplete();

  // Initialize local-only state
  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString('username');

  if (isSetupComplete && username == null) {
    debugPrint("Setup complete but no user found. Resetting...");
    isSetupComplete = false;
    await storage.setSetupComplete(false);
  }

  // Set local mode by default
  if (isSetupComplete) {
    await storage.setIsLocalMode(true);
  }

  if (isSetupComplete && username != null) {
    // Initialize database service for the user to start background coalescing
    // Don't block app startup for this
    unawaited(DatabaseService.instance.initForUser(username));
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
      home: (!isSetupComplete || !authState.isAuthenticated)
          ? const SetupScreen()
          : const MainScreen(),
    );
  }
}

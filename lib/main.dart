import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:metadata_god/metadata_god.dart';
import 'presentation/screens/main_screen.dart';
import 'providers/auth_provider.dart';
import 'services/cache_service.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/screens/setup_screen.dart';
import 'providers/setup_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'dart:async';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

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
  PaintingBinding.instance.imageCache.maximumSize = 100; // Reduced from 200
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      30 * 1024 * 1024; // Reduced from 50MB

  HttpOverrides.global = MyHttpOverrides();

  // Check setup status and migration
  final storage = StorageService();
  bool isSetupComplete = await storage.getIsSetupComplete();
  final oldUrl = await storage.getServerUrl();

  // Migration: If not setup V2 but has old URL, force logout
  if (!isSetupComplete && oldUrl != null) {
    debugPrint("Legacy user detected, forcing setup...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    // We treat them as new user for the setup flow
  }

  // Initialize API/State based on findings
  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString('username');

  if (isSetupComplete && username == null) {
    debugPrint("Setup complete but no user found. Resetting...");
    isSetupComplete = false;
    await storage.setSetupComplete(false);
  }

  if (isSetupComplete) {
    final isLocal = await storage.getIsLocalMode();
    if (!isLocal) {
      final savedUrl = await storage.getServerUrl();
      if (savedUrl != null && savedUrl.isNotEmpty) {
        ApiService.setBaseUrl(savedUrl);
      }
    } else {
      // If in local mode, ensure the API URL is cleared to prevent any accidental syncs
      ApiService.setBaseUrl("");
    }
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
    child: const GruSongsApp(),
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

class GruSongsApp extends ConsumerWidget {
  const GruSongsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isSetupComplete = ref.watch(setupProvider);
    final themeState = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Gru Songs',
      debugShowCheckedModeBanner: false,
      theme: GruTheme.getTheme(themeState.mode),
      home: (!isSetupComplete || !authState.isAuthenticated)
          ? const SetupScreen()
          : const MainScreen(),
    );
  }
}

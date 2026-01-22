import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'presentation/screens/main_screen.dart';
import 'providers/auth_provider.dart';
import 'services/cache_service.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/screens/setup_screen.dart';
import 'providers/setup_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Cache V3 and cleanup legacy caches
  await CacheService.instance.init();

  // Limit image cache to save RAM
  PaintingBinding.instance.imageCache.maximumSize = 200; // images
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      50 * 1024 * 1024; // 50MB

  await AudioSession.instance.then(
      (session) => session.configure(const AudioSessionConfiguration.music()));

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sillygru.gru_songs.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: false,
  );

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

  runApp(ProviderScope(
    overrides: [
      setupProvider
          .overrideWith(() => InitializedSetupNotifier(isSetupComplete)),
      authProvider.overrideWith(() => PreloadedAuthNotifier(username)),
    ],
    child: const GruSongsApp(),
  ));
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

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
import 'providers/providers.dart';
import 'services/cache_service.dart';
import 'services/storage_service.dart';
import 'services/database_service.dart';
import 'services/color_extraction_service.dart';
import 'services/update_service.dart';
import 'presentation/widgets/update_available_dialog.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallel initialization
  await Future.wait([
    _initializeMetadataGod(),
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
    await storage.setIsLocalMode(true);
    unawaited(Future.microtask(() => runApp(ProviderScope(
          overrides: [
            setupProvider
                .overrideWith(() => InitializedSetupNotifier(isSetupComplete)),
            authProvider.overrideWith(() => PreloadedAuthNotifier(username)),
          ],
          child: const WispieApp(),
        ))));
    return;
  }

  await storage.setIsLocalMode(true);

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

class WispieApp extends ConsumerStatefulWidget {
  const WispieApp({super.key});

  @override
  ConsumerState<WispieApp> createState() => _WispieAppState();
}

class _WispieAppState extends ConsumerState<WispieApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(CacheService.instance.init());
      unawaited(ColorExtractionService.init());
      unawaited(CacheService.instance.scheduleStartupMaintenance());
      unawaited(
        ref.read(updateCheckProvider.notifier).prime().then((_) {
          if (mounted) _checkAndShowUpdateDialog();
        }).catchError((_) {}),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkAndShowUpdateDialog() async {
    if (_updateDialogShown) return;
    // Don't interrupt the setup flow.
    if (!ref.read(setupProvider)) return;

    final state = ref.read(updateCheckProvider);
    if (!state.hasUpdate) return;

    try {
      final dismissed =
          await UpdateService.isVersionDismissed(state.latestTag!);
      if (!mounted || _updateDialogShown || dismissed) return;

      _updateDialogShown = true;
      final dialogContext = _navigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) return;
      showUpdateAvailableDialog(
        dialogContext,
        currentVersion: state.currentVersion,
        newVersion: state.latestVersionLabel ?? state.latestTag!,
        dismissalTag: state.latestTag!,
        releaseUrl:
            state.releaseUrl ?? Uri.parse(UpdateService.latestReleaseUrl),
      );
    } catch (_) {
      // Fail silently — update dialogs are best-effort.
    }
  }

  @override
  void didHaveMemoryPressure() {
    ref.read(audioPlayerManagerProvider).onMemoryPressure();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS && state != AppLifecycleState.resumed) {
      unawaited(ref.read(audioPlayerManagerProvider).forceFlushCurrentStats());
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isSetupComplete = ref.watch(setupProvider);
    final themeState = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Wispie',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
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

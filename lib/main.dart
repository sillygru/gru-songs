import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/providers.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  
  await AudioSession.instance.then((session) => session.configure(const AudioSessionConfiguration.music()));
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sillygru.gru_songs.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  runApp(const ProviderScope(child: GruSongsApp()));
}

class GruSongsApp extends ConsumerWidget {
  const GruSongsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    // Inject service into notifier
    if (authState.isAuthenticated) {
      // Defer to next frame to avoid build issues
      Future.microtask(() {
         ref.read(userDataProvider.notifier).setService(ref.read(userDataServiceProvider));
      });
    }
    
    return MaterialApp(
      title: 'Gru Songs',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: authState.isAuthenticated ? const MainScreen() : const AuthScreen(),
    );
  }
}

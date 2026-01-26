import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import '../widgets/now_playing_bar.dart';
import '../../providers/providers.dart';

class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final isScanning = ref.watch(isScanningProvider);
    final metadataState = ref.watch(metadataSaveProvider);

    return FutureBuilder<bool>(
      future: ref.read(storageServiceProvider).getIsLocalMode(),
      builder: (context, snapshot) {
        final isLocalMode = snapshot.data ?? false;
        if (isLocalMode && !isScanning) return const SizedBox.shrink();
        if (syncState.status == SyncStatus.idle &&
            !syncState.hasError &&
            !isScanning &&
            metadataState.status == MetadataSaveStatus.idle) {
          return const SizedBox.shrink();
        }

        Color bgColor = Colors.blue;
        String text = "Syncing...";
        IconData icon = Icons.sync;
        bool showSpinner = false;

        if (isScanning) {}

        if (metadataState.status == MetadataSaveStatus.saving) {
          showSpinner = true;
          bgColor = Colors.orange.shade800;
          text = metadataState.message;
          icon = Icons.edit;
        } else if (metadataState.status == MetadataSaveStatus.success) {
          bgColor = Colors.green.shade700;
          text = metadataState.message;
          icon = Icons.check_circle;
        } else if (metadataState.status == MetadataSaveStatus.error) {
          bgColor = Colors.red.shade700;
          text = metadataState.message;
          icon = Icons.error;
        } else if (syncState.status == SyncStatus.idle || syncState.hasError) {
          bgColor = Colors.orange.shade900;
          text = "Offline - Using Cached Data";
          icon = Icons.cloud_off;
        }

        if (!showSpinner &&
            syncState.status == SyncStatus.idle &&
            !syncState.hasError &&
            metadataState.status == MetadataSaveStatus.idle) {
          return const SizedBox.shrink();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                color: bgColor,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showSpinner)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(icon, size: 14, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const LibraryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Trigger background refresh when app returns to foreground
      // This will use the optimized scanner we just implemented
      ref.read(songsProvider.notifier).refresh(isBackground: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: const SyncIndicator(),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NowPlayingBar(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import '../widgets/now_playing_bar.dart';
import '../widgets/app_drawer.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../../services/telemetry_service.dart';
import '../widgets/bulk_selection_bar.dart';
import '../widgets/immersive_background.dart';
import '../widgets/auto_backup_indicator.dart';

class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});
// ... (SyncIndicator implementation remains the same)

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

        if (isScanning) {
          showSpinner = true;
          bgColor = Colors.blue.shade700;
          text = "Scanning Library...";
          icon = Icons.search;
        } else if (metadataState.status == MetadataSaveStatus.saving) {
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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isDrawerOpen = false;

  // Gesture detection for drawer
  double _dragStartX = 0;
  bool _isDraggingFromEdge = false;
  static const double _edgeDragWidth = 60.0;
  static const double _minDragDistance = 30.0;

  // Track which screens have been built to enable lazy loading
  final Set<int> _builtScreens = {0};

  final List<Widget> _screens = [
    const HomeScreen(),
    const LibraryScreen(),
    const ProfileScreen(),
  ];

  void _openDrawer() {
    setState(() {
      _isDrawerOpen = true;
    });
  }

  void _closeDrawer() {
    setState(() {
      _isDrawerOpen = false;
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
      _builtScreens.add(index);
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // Check if drag starts from left edge
    if (details.globalPosition.dx <= _edgeDragWidth && !_isDrawerOpen) {
      _isDraggingFromEdge = true;
      _dragStartX = details.globalPosition.dx;
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isDraggingFromEdge && !_isDrawerOpen) {
      final dragDistance = details.globalPosition.dx - _dragStartX;
      if (dragDistance > _minDragDistance) {
        _openDrawer();
        _isDraggingFromEdge = false;
      }
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDraggingFromEdge = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Track app launch (Level 1)
    TelemetryService.instance.trackEvent('app_launch', {}, requiredLevel: 1);
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
      
      // Check and run auto-backup if needed
      ref.read(autoBackupProvider.notifier).checkAndRunAutoBackup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    final isSelectionMode =
        ref.watch(selectionProvider.select((s) => s.isSelectionMode));

    return Scaffold(
      body: PopScope(
        canPop: !isSelectionMode,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (isSelectionMode) {
            ref.read(selectionProvider.notifier).exitSelectionMode();
          }
        },
        child: GestureDetector(
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              ImmersiveBackground(
                child: Stack(
                  children: _screens.asMap().entries.map((entry) {
                    final index = entry.key;
                    final screen = entry.value;
                    // Only build if this screen has been selected before
                    if (!_builtScreens.contains(index)) {
                      return const SizedBox.shrink();
                    }
                    return Offstage(
                      offstage: index != _selectedIndex,
                      child: TickerMode(
                        enabled: index == _selectedIndex,
                        child: screen,
                      ),
                    );
                  }).toList(),
                ),
              ),
              Positioned(
                top: topPadding,
                left: 0,
                right: 0,
                child: const SyncIndicator(),
              ),
              Positioned(
                top: topPadding + 40,
                left: 0,
                right: 0,
                child: const AutoBackupIndicator(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: isSelectionMode
                    ? const BulkSelectionBar()
                    : const NowPlayingBar(),
              ),
              // Drawer overlay
              if (_isDrawerOpen)
                Positioned.fill(
                  child: AppDrawer(onClose: _closeDrawer),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isSelectionMode
          ? null
          : Container(
              padding: const EdgeInsets.only(bottom: 8),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onTabSelected,
                indicatorColor:
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
    );
  }
}

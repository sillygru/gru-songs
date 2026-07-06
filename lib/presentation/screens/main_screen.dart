import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import '../widgets/now_playing_bar.dart';
import '../widgets/app_drawer.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/telemetry_service.dart';
import '../widgets/bulk_selection_bar.dart';
import '../widgets/immersive_background.dart';
import '../widgets/auto_backup_indicator.dart';

class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScanning = ref.watch(isScanningProvider);
    final metadataState = ref.watch(metadataSaveProvider);

    if (!isScanning && metadataState.status == MetadataSaveStatus.idle) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    String text;
    IconData icon;
    bool showSpinner;

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
      showSpinner = false;
      bgColor = Colors.green.shade700;
      text = metadataState.message;
      icon = Icons.check_circle;
    } else {
      showSpinner = false;
      bgColor = Colors.red.shade700;
      text = metadataState.message;
      icon = Icons.error;
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
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isDrawerOpen = false;

  late AnimationController _drawerController;

  bool _isDraggingDrawer = false;

  static const double _bottomDockBaseHeight = 88.0;

  // Gesture detection for drawer
  static const double _edgeDragWidth = 60.0;
  static const double _drawerWidthRatio = 0.8;

  // Track which screens have been built to enable lazy loading
  final Set<int> _builtScreens = {0};

  late final List<ScrollController> _scrollControllers;

  List<Widget> get _screens => [
        HomeScreen(scrollController: _scrollControllers[0]),
        LibraryScreen(scrollController: _scrollControllers[1]),
        ProfileScreen(scrollController: _scrollControllers[2]),
      ];

  Future<void> _closeDrawer() async {
    if (!_isDrawerOpen && !_drawerController.isAnimating) return;
    await _drawerController.animateTo(0.0, curve: Curves.easeOutCubic);
    if (mounted) {
      setState(() {
        _isDrawerOpen = false;
      });
    }
  }

  void _onTabSelected(int index) {
    if (index == _selectedIndex) {
      _scrollControllers[index].animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      setState(() {
        _selectedIndex = index;
        _builtScreens.add(index);
      });
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_isDrawerOpen || details.globalPosition.dx <= _edgeDragWidth) {
      _isDraggingDrawer = true;
      _drawerController.stop();
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingDrawer) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx / (screenWidth * _drawerWidthRatio);

    _drawerController.value = (_drawerController.value + delta).clamp(0.0, 1.0);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDraggingDrawer) return;
    _isDraggingDrawer = false;

    if (_drawerController.value > 0.45) {
      setState(() => _isDrawerOpen = true);
      _drawerController.animateTo(1.0, curve: Curves.easeOutCubic);
    } else {
      _drawerController.animateTo(0.0, curve: Curves.easeOutCubic).then((_) {
        if (mounted) setState(() => _isDrawerOpen = false);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scrollControllers = List.generate(3, (_) => ScrollController());
    WidgetsBinding.instance.addObserver(this);
    // Report app launch telemetry
    unawaited(TelemetryService.instance.reportLaunch());

    // Check and run auto-backup on initial app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(autoBackupProvider.notifier).checkAndRunAutoBackup();
    });
  }

  @override
  void dispose() {
    _drawerController.dispose();
    for (final c in _scrollControllers) {
      c.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Trigger background refresh when app returns to foreground
      ref.read(songsProvider.notifier).refresh(isBackground: true);

      // Check and run auto-backup if needed
      ref.read(autoBackupProvider.notifier).checkAndRunAutoBackup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final settings = ref.watch(settingsProvider);
    final topPadding = mediaQuery.padding.top;
    final androidSystemBottomInset = mediaQuery.padding.bottom;
    final bottomDockState = ref.watch(bottomDockVisibilityProvider);
    final bottomDockVisibility =
        settings.autoHideBottomBarOnScroll ? bottomDockState.visibility : 1.0;
    final isBottomDockHidden = bottomDockVisibility <= 0.001;
    final bottomInsetReduced = Platform.isIOS
        ? (androidSystemBottomInset > 0 ? 10.0 : 0.0)
        : androidSystemBottomInset;
    final bottomDockHeight = _bottomDockBaseHeight + bottomInsetReduced;
    final nowPlayingBottomPadding = settings.autoHideBottomBarOnScroll &&
            isBottomDockHidden &&
            androidSystemBottomInset > 0
        ? Platform.isIOS
            ? 12.0
            : 8.0 + androidSystemBottomInset
        : settings.autoHideBottomBarOnScroll && isBottomDockHidden
            ? Platform.isIOS
                ? 16.0
                : 20.0
            : 12.0;

    final isSelectionMode =
        ref.watch(selectionProvider.select((s) => s.isSelectionMode));
    ref.listen(
      settingsProvider.select((value) => value.autoHideBottomBarOnScroll),
      (previous, next) {
        if (!next) {
          ref.read(bottomDockVisibilityProvider.notifier).show();
        }
      },
    );

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
              // Drawer sits underneath the main content
              if (_isDrawerOpen ||
                  _isDraggingDrawer ||
                  _drawerController.isAnimating)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _drawerController,
                    builder: (context, child) => AppDrawer(
                      onClose: _closeDrawer,
                      drawerPosition: _drawerController.value,
                    ),
                  ),
                ),
              // Main content slides right to reveal the drawer
              AnimatedBuilder(
                animation: _drawerController,
                builder: (context, child) {
                  final slideX =
                      _drawerController.value * mediaQuery.size.width * 0.8;
                  return RepaintBoundary(
                    child: Transform.translate(
                      offset: Offset(slideX, 0),
                      child: Stack(
                        children: [
                          child!,
                          // Scrim dims the content when drawer is open
                          if (_isDrawerOpen ||
                              _isDraggingDrawer ||
                              _drawerController.isAnimating)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: _closeDrawer,
                                child: Container(
                                  color: Colors.black.withValues(
                                    alpha: 0.45 * _drawerController.value,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    ImmersiveBackground(
                      child: Stack(
                        children: _screens.asMap().entries.map((entry) {
                          final index = entry.key;
                          final screen = entry.value;
                          if (!_builtScreens.contains(index)) {
                            // Only build if this screen has been selected before
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
                          : NowPlayingBar(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                0,
                                12,
                                nowPlayingBottomPadding,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isSelectionMode
          ? null
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 1,
                end: bottomDockVisibility,
              ),
              duration: bottomDockState.isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: bottomDockState.isDragging
                  ? Curves.linear
                  : Curves.easeOutCubic,
              builder: (context, value, child) {
                return SizedBox(
                  height: bottomDockHeight * value,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 24),
                        child: Opacity(
                          opacity: value.clamp(0, 1).toDouble(),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onTabSelected,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
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
            ),
    );
  }
}

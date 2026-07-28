import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/song.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/setup_provider.dart';
import '../../services/storage_service.dart';
import '../components/ambient_scaffold.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../components/app_list_row.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';
import '../widgets/wispie_ghost_widget.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final TextEditingController _usernameController = TextEditingController();

  late final AnimationController _introController; // one-shot entrance swoop
  late final AnimationController _outroController; // one-shot fly-away
  // Slow ambient drift for parallax dust. Coprime with the ghost's internal
  // float so the scene never retraces.
  late final AnimationController _ambientController;

  int _currentPage = 0;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _permissionDeniedOnce = false;
  bool _showIntroScreen = true;

  List<Map<String, String>> _musicFolders = [];

  @override
  void initState() {
    super.initState();
    _loadInitialFolders();
    _checkPermissionStatus();

    // Entrance swoop: anticipation -> swoop -> settle.
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    // Fly-away outro (driven on Finish).
    _outroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  Future<void> _loadInitialFolders() async {
    final storage = StorageService();
    final folders = await storage.getMusicFolders();
    if (mounted) {
      setState(() => _musicFolders = folders);
    }
  }

  Future<void> _checkPermissionStatus() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (mounted) {
        setState(() => _permissionGranted = status.isGranted);
      }
    } else {
      setState(() => _permissionGranted = true);
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    _outroController.dispose();
    _ambientController.dispose();
    _pageController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: AppTokens.dSlow,
        curve: AppTokens.cEmphasized,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: AppTokens.dBase,
        curve: AppTokens.cStandard,
      );
    }
  }

  GhostExpression get _ghostExpression {
    switch (_currentPage) {
      case 0:
        return _usernameController.text.trim().isNotEmpty
            ? GhostExpression.excited
            : GhostExpression.happy;
      case 1:
        return GhostExpression.appearance;
      case 2:
        return GhostExpression.searching;
      case 3:
        return GhostExpression.celebrate;
      default:
        return GhostExpression.happy;
    }
  }

  String get _ghostSpeechText {
    final name = _usernameController.text.trim();
    switch (_currentPage) {
      case 0:
        if (name.isNotEmpty) {
          return 'Awesome to meet you, $name! Let\'s customize Wispie for you.';
        }
        return 'What should I call you friend?';
      case 1:
        return 'Here are your appearance settings!';
      case 2:
        return 'Now, let\'s find your music! Select the folders where your audio files live.';
      case 3:
        return 'Everything is set up! Let\'s get started!';
      default:
        return 'Welcome to Wispie!';
    }
  }

  Future<void> _addFolder() async {
    final storage = StorageService();
    final selection = await storage.pickMusicFolder(context);
    if (selection == null || selection['path']!.isEmpty) {
      if (mounted) {
        appSnack(context, 'Unable to access selected folder');
      }
      return;
    }

    await storage.addMusicFolder(
      selection['path']!,
      selection['treeUri'],
      iosBookmarkId: selection['iosBookmarkId'],
      platform: selection['platform'],
    );

    ref.invalidate(musicFoldersProvider);
    ref.invalidate(songsProvider);
    await _loadInitialFolders();

    if (mounted) {
      appSnack(context, 'Music folder added');
    }
  }

  Future<void> _removeFolder(Map<String, String> folder) async {
    final storage = StorageService();
    await storage.removeMusicFolder(
      folder['path'] ?? '',
      iosBookmarkId: folder['iosBookmarkId'],
    );

    ref.invalidate(musicFoldersProvider);
    ref.invalidate(songsProvider);
    await _loadInitialFolders();

    if (mounted) {
      appSnack(context, 'Music folder removed');
    }
  }

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid) return;

    setState(() => _isLoading = true);

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      setState(() {
        _permissionGranted = true;
        _isLoading = false;
      });
      return;
    }

    if (status.isPermanentlyDenied) {
      setState(() {
        _permissionDeniedOnce = true;
        _isLoading = false;
      });
      await openAppSettings();
      status = await Permission.manageExternalStorage.status;
      if (status.isGranted && mounted) {
        setState(() => _permissionGranted = true);
      }
      return;
    }

    status = await Permission.manageExternalStorage.request();
    if (status.isGranted && mounted) {
      setState(() => _permissionGranted = true);
    } else if (status.isPermanentlyDenied && mounted) {
      setState(() => _permissionDeniedOnce = true);
    } else if (mounted) {
      appSnack(
        context,
        'Storage permission is required to scan your music library.',
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeFinishSetup() async {
    final name = _usernameController.text.trim();
    if (name.isEmpty) {
      appSnack(context, 'Please enter a display name');
      _pageController.animateToPage(
        0,
        duration: AppTokens.dBase,
        curve: AppTokens.cStandard,
      );
      return;
    }

    setState(() => _isLoading = true);

    // Play the fly-away before completing setup.
    await _outroController.forward();

    try {
      final storage = StorageService();
      await storage.setIsLocalMode(true);
      await storage.setSetupComplete(true);

      await ref.read(authProvider.notifier).setDisplayName(name);
      ref.read(setupProvider.notifier).setComplete(true);
    } catch (e) {
      if (mounted) {
        appSnack(context, 'Setup error: $e');
        _outroController.reverse(); // Bring ghost back if it fails.
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ------------------------------------------------------------- INTRO SCREEN
  Widget _buildFullscreenIntro() {
    final accent = AppTokens.accentOf(context, ref);

    return AnimatedBuilder(
      animation: Listenable.merge([_introController, _ambientController]),
      builder: (context, child) {
        final intro = _introController.value;

        // Entrance swoop arc.
        final swoop = _SwoopCurve.transform(intro);
        final ghostX = swoop.dx;
        final ghostY = swoop.dy;

        // Staggered title opacity & slide.
        final titleP = const Interval(0.45, 0.9, curve: Curves.easeOutCubic)
            .transform(intro);
        final titleY = (1 - titleP) * 24.0;

        // Staggered button opacity & slide.
        final buttonP = const Interval(0.62, 1.0, curve: Curves.easeOutCubic)
            .transform(intro);
        final buttonY = (1 - buttonP) * 28.0;

        return Stack(
          children: [
            // Parallax ambient dust.
            Positioned.fill(
              child: CustomPaint(
                painter: _AmbientDustPainter(
                  t: _ambientController.value,
                  accentColor: accent,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    Transform.translate(
                      offset: Offset(ghostX, ghostY),
                      child: Transform.scale(
                        scale: swoop.scale.clamp(0.1, 1.0),
                        child: WispieGhostWidget(
                          speechText: 'Welcome to wispie!',
                          expression: GhostExpression.excited,
                          ghostSize: 135,
                          idleFloat: _introController.isCompleted,
                          showSpeechBubble: _introController.isCompleted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Transform.translate(
                      offset: Offset(0, titleY),
                      child: Opacity(
                        opacity: titleP.clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            Text(
                              'WISPIE',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8,
                                color: AppTokens.fgPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your Personal Music Companion',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppTokens.fgSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    Transform.translate(
                      offset: Offset(0, buttonY),
                      child: Opacity(
                        opacity: buttonP.clamp(0.0, 1.0),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _showIntroScreen = false;
                              });
                            },
                            icon: const AppIcon(AppIcons.arrowForward),
                            label: const Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: AppTokens.onAccent(accent),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppTokens.brPill,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMainSetupScreen() {
    final accent = AppTokens.accentOf(context, ref);

    return SafeArea(
      child: Column(
        children: [
          // Top header & step progress bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                if (_currentPage > 0)
                  IconButton(
                    icon: const AppIcon(AppIcons.arrowBack),
                    onPressed: _previousPage,
                    tooltip: 'Previous step',
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isActive = index == _currentPage;
                      final isCompleted = index < _currentPage;

                      return AnimatedContainer(
                        duration: AppTokens.dSlow,
                        curve: AppTokens.cEmphasized,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6,
                        width: isActive ? 28 : 10,
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent
                              : isCompleted
                                  ? accent.withValues(alpha: 0.5)
                                  : AppTokens.surface(2),
                          borderRadius: AppTokens.brPill,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),

          // Animated mascot section.
          SizedBox(
            height: 215,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _outroController,
                  builder: (context, child) {
                    final v = _outroController.value;
                    double dy = 0;
                    double dx = 0;
                    double scale = 1;
                    double tilt = 0;
                    double opacity = 1;

                    if (v == 0) {
                      // Resting: ghost idles on its own.
                    } else if (v < 0.16) {
                      final c = v / 0.16;
                      final arc = math.sin(c * math.pi);
                      dy = arc * 16.0;
                      scale = 1.0 - arc * 0.07;
                    } else {
                      final lt = (v - 0.16) / 0.84;
                      final launch = lt * lt;
                      dy = -launch * constraints.maxHeight * 3.8;
                      dx = math.sin(lt * math.pi) * 60.0;
                      tilt = lt * 1.8;
                      scale = (1.0 - launch * 0.45).clamp(0.1, 1.0);
                      opacity = (1.0 - ((lt - 0.55) / 0.45).clamp(0.0, 1.0))
                          .clamp(0.0, 1.0);
                    }

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (v > 0.16 && v < 0.98)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FlyAwayTrailPainter(
                                progress: v,
                                dy: dy,
                                dx: dx,
                                tilt: tilt,
                                scale: scale,
                                accent: accent,
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: Offset(dx, dy),
                          child: Transform.rotate(
                            angle: tilt,
                            child: Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: opacity,
                                child: Align(
                                  alignment: const Alignment(0, 0.52),
                                  child: WispieGhostWidget(
                                    speechText: _ghostSpeechText,
                                    expression: _ghostExpression,
                                    ghostSize: 110,
                                    idleFloat: v == 0,
                                    showSpeechBubble: v == 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Page view with staggered step screens.
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) => setState(() => _currentPage = page),
              children: [
                _StaggeredStepWrapper(
                  stepKey: const ValueKey('step_0'),
                  child: _buildNameStep(),
                ),
                _StaggeredStepWrapper(
                  stepKey: const ValueKey('step_1'),
                  child: _buildAppearanceStep(),
                ),
                _StaggeredStepWrapper(
                  stepKey: const ValueKey('step_2'),
                  child: _buildFoldersStep(),
                ),
                _StaggeredStepWrapper(
                  stepKey: const ValueKey('step_3'),
                  child: _buildReadyStep(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntroScreen) {
      return AmbientScaffold(
        body: _buildFullscreenIntro(),
      );
    }

    return AmbientScaffold(
      body: _buildMainSetupScreen(),
    );
  }

  // ------------------------------------------------------------- STEP 1: NAME
  Widget _buildNameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StaggeredItem(
            delay: const Duration(milliseconds: 80),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTokens.surface(1),
                borderRadius: AppTokens.brLg,
                boxShadow: AppTokens.shadowRaised,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Display Name',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTokens.fgPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is how Wispie will greet you in your music dashboard.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.fgSecondary,
                        ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      hintText: 'Enter your name',
                      prefixIcon: AppIcon(AppIcons.person),
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      if (_usernameController.text.trim().isNotEmpty) {
                        _nextPage();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _StaggeredItem(
            delay: const Duration(milliseconds: 220),
            child: FilledButton.icon(
              onPressed: _usernameController.text.trim().isEmpty
                  ? null
                  : () => _nextPage(),
              icon: const AppIcon(AppIcons.arrowForward),
              label: const Text('Continue to Appearance'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- STEP 2: APPEARANCE
  Widget _buildAppearanceStep() {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final accent = AppTokens.accentOf(context, ref);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StaggeredItem(
            delay: const Duration(milliseconds: 80),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTokens.surface(1),
                borderRadius: AppTokens.brLg,
                boxShadow: AppTokens.shadowRaised,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppRowIcon(
                        icon: AppIcons.tune,
                        color: accent,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Motion & Display Settings',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTokens.fgPrimary,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Visualizer Mode Dropdown
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Audio Visualizer'),
                    subtitle: const Text('Playback visualizer effect'),
                    trailing: DropdownButton<VisualizerMode>(
                      value: settings.visualizerMode,
                      underline: const SizedBox.shrink(),
                      borderRadius: AppTokens.brMd,
                      onChanged: (val) {
                        if (val != null) notifier.setVisualizerMode(val);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: VisualizerMode.off,
                          child: Text('Off'),
                        ),
                        DropdownMenuItem(
                          value: VisualizerMode.classic,
                          child: Text('Classic'),
                        ),
                        DropdownMenuItem(
                          value: VisualizerMode.synced,
                          child: Text('Synced'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Player Motion Intensity
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Motion Intensity'),
                    subtitle: const Text('Beat reaction & motion strength'),
                    trailing: DropdownButton<PlayerMotionIntensity>(
                      value: settings.playerMotionIntensity,
                      underline: const SizedBox.shrink(),
                      borderRadius: AppTokens.brMd,
                      onChanged: (val) {
                        if (val != null) notifier.setPlayerMotionIntensity(val);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: PlayerMotionIntensity.subtle,
                          child: Text('Subtle'),
                        ),
                        DropdownMenuItem(
                          value: PlayerMotionIntensity.balanced,
                          child: Text('Balanced'),
                        ),
                        DropdownMenuItem(
                          value: PlayerMotionIntensity.bold,
                          child: Text('Bold'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Beat-reactive cover toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Beat-reactive Cover'),
                    subtitle: const Text('Pulse album art to music beat'),
                    value: settings.beatReactiveCoverEnabled,
                    onChanged: notifier.setBeatReactiveCoverEnabled,
                  ),

                  // Beat-reactive particles toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Beat-reactive Particles'),
                    subtitle: const Text('Floating music particles in player'),
                    value: settings.beatReactiveParticlesEnabled,
                    onChanged: notifier.setBeatReactiveParticlesEnabled,
                  ),

                  // Waveform toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Waveform Progress Bar'),
                    subtitle: const Text('Show visual audio waveform'),
                    value: settings.showWaveform,
                    onChanged: notifier.setShowWaveform,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _StaggeredItem(
            delay: const Duration(milliseconds: 220),
            child: FilledButton.icon(
              onPressed: _nextPage,
              icon: const AppIcon(AppIcons.arrowForward),
              label: const Text('Continue to Music Folders'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- STEP 3: FOLDERS
  Widget _buildFoldersStep() {
    final accent = AppTokens.accentOf(context, ref);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Platform.isAndroid && !_permissionGranted) ...[
            _StaggeredItem(
              delay: const Duration(milliseconds: 80),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTokens.surface(1),
                  borderRadius: AppTokens.brLg,
                ),
                child: Column(
                  children: [
                    const AppIcon(AppIcons.storage, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Storage Permission Needed',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Wispie needs permission to access audio files on your device.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTokens.fgSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _requestPermission,
                      icon: const AppIcon(AppIcons.folder),
                      label: Text(_permissionDeniedOnce
                          ? 'Open System Settings'
                          : 'Grant Permission'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: _StaggeredItem(
              delay: const Duration(milliseconds: 160),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTokens.surface(1),
                  borderRadius: AppTokens.brLg,
                  boxShadow: AppTokens.shadowRaised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Music Folders (${_musicFolders.length})',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTokens.fgPrimary,
                                  ),
                        ),
                        TextButton.icon(
                          onPressed: _addFolder,
                          icon: const AppIcon(AppIcons.add, size: 18),
                          label: const Text('Add Folder'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _musicFolders.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AppIcon(
                                    AppIcons.folder,
                                    size: 44,
                                    color: accent.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No music folders added yet',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppTokens.fgSecondary,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap Add Folder above to choose where your songs are stored.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppTokens.fgTertiary,
                                        ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _musicFolders.length,
                              itemBuilder: (context, index) {
                                final folder = _musicFolders[index];
                                final path = folder['path'] ?? '';
                                final name = path.split('/').last;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTokens.surface(2),
                                    borderRadius: AppTokens.brMd,
                                  ),
                                  child: ListTile(
                                    leading: AppRowIcon(
                                      icon: AppIcons.folder,
                                      color: accent,
                                    ),
                                    title: Text(
                                      name.isEmpty ? path : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: IconButton(
                                      icon: const AppIcon(AppIcons.delete,
                                          size: 18),
                                      onPressed: () => _removeFolder(folder),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StaggeredItem(
            delay: const Duration(milliseconds: 300),
            child: FilledButton.icon(
              onPressed: _nextPage,
              icon: const AppIcon(AppIcons.arrowForward),
              label: const Text('Continue to Final Step'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- STEP 4: READY
  Widget _buildReadyStep() {
    final settings = ref.watch(settingsProvider);
    final accent = AppTokens.accentOf(context, ref);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StaggeredItem(
            delay: const Duration(milliseconds: 80),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTokens.surface(1),
                borderRadius: AppTokens.brLg,
                boxShadow: AppTokens.shadowRaised,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppRowIcon(
                        icon: AppIcons.checkCircle,
                        color: accent,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Setup Summary',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTokens.fgPrimary,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildSummaryRow(
                    'User Profile',
                    _usernameController.text.trim().isEmpty
                        ? 'Guest'
                        : _usernameController.text.trim(),
                    AppIcons.person,
                  ),
                  const SizedBox(height: 10),
                  _buildSummaryRow(
                    'Visualizer Mode',
                    settings.visualizerMode.name.toUpperCase(),
                    AppIcons.waves,
                  ),
                  const SizedBox(height: 10),
                  _buildSummaryRow(
                    'Music Folders',
                    '${_musicFolders.length} selected',
                    AppIcons.folder,
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Telemetry toggle
                  Consumer(
                    builder: (context, ref, child) {
                      final currentSettings = ref.watch(settingsProvider);
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Anonymous telemetry'),
                        subtitle: const Text(
                          'Help improve Wispie with anonymous usage stats. No personal data is collected.',
                        ),
                        value: currentSettings.telemetryEnabled,
                        onChanged: (val) {
                          ref
                              .read(settingsProvider.notifier)
                              .setTelemetryEnabled(val);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _StaggeredItem(
            delay: const Duration(milliseconds: 220),
            child: FilledButton(
              onPressed: _isLoading ? null : _executeFinishSetup,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: accent,
                foregroundColor: AppTokens.onAccent(accent),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text(
                      'Start Listening',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, AppIconData icon) {
    return Row(
      children: [
        AppIcon(icon, size: 18, color: AppTokens.fgSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.fgSecondary,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: AppTokens.fgPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// A real three-phase entrance: anticipation (small dip + shrink back) -> swoop
/// (arc forward, rising over the middle) -> settle (gentle ease-out with a
/// single soft overshoot). Returns decorrelated x/y/scale so the path is an
/// arc, not a straight diagonal.
class _SwoopCurve {
  const _SwoopCurve._();

  static _SwoopState transform(double t) {
    const anticipEnd = 0.14;
    const swoopEnd = 0.62;

    const startX = -220.0;
    const startY = 120.0;

    double dx, dy, scale;

    if (t < anticipEnd) {
      // Anticipation: pull slightly backward and dip down.
      final a = t / anticipEnd;
      final e = Curves.easeOut.transform(a);
      dx = startX - 15.0 * e;
      dy = startY + 15.0 * e;
      scale = 0.95 - 0.05 * e;
    } else if (t < swoopEnd) {
      // Swoop: arc forward and rise over the middle.
      final a = (t - anticipEnd) / (swoopEnd - anticipEnd);
      final eased = Curves.easeInOutCubic.transform(a);
      dx = (startX - 15.0) + ((-12.0) - (startX - 15.0)) * eased;
      dy = (startY + 15.0) - math.sin(a * math.pi) * 140.0 - eased * 147.0;
      scale = 0.90 + 0.12 * Curves.easeOut.transform(a);
    } else {
      // Settle: ease into rest position (0, 0).
      final a = (t - swoopEnd) / (1.0 - swoopEnd);
      final eX = Curves.easeOutBack.transform(a);
      final eY = Curves.easeOutCubic.transform(a);
      dx = -12.0 + (0.0 - (-12.0)) * eX;
      dy = -25.0 + (0.0 - (-25.0)) * eY;
      scale = 1.02 - 0.02 * eY;
    }

    return _SwoopState(dx, dy, scale);
  }
}

class _SwoopState {
  final double dx;
  final double dy;
  final double scale;
  const _SwoopState(this.dx, this.dy, this.scale);
}

/// Fades + slides a child in with a short delay, used to cascade step content.
class _StaggeredItem extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _StaggeredItem({
    required this.delay,
    required this.child,
  });

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _StaggeredStepWrapper extends StatelessWidget {
  final Key stepKey;
  final Widget child;

  const _StaggeredStepWrapper({
    required this.stepKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppTokens.dSlow,
      switchInCurve: AppTokens.cEmphasized,
      switchOutCurve: AppTokens.cStandard,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.08, 0.0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: stepKey,
        child: child,
      ),
    );
  }
}

/// Ambient dust with three parallax layers and per-particle twinkle. Particles
/// are pre-seeded once (stable identities) and drift + shimmer over time, so
/// the field reads as floating depth rather than a scrolling screensaver.
class _AmbientDustPainter extends CustomPainter {
  final double t; // 0..1 looping over a long period
  final Color accentColor;

  _AmbientDustPainter({required this.t, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(7);
    final paint = Paint()..style = PaintingStyle.fill;
    final phase = t * math.pi * 2;

    // Far layer: tiny, slow, dim, drifts least (max parallax).
    _drawLayer(
      canvas,
      size,
      rand,
      paint,
      phase,
      count: 26,
      radiusMin: 0.8,
      radiusRange: 1.8,
      driftAmp: 6.0,
      driftSpeed: 0.6,
      twinkleAmp: 0.12,
      twinkleSpeed: 1.0,
      baseAlpha: 0.06,
      color: Colors.white,
    );

    // Mid layer: medium, accent-tinted.
    _drawLayer(
      canvas,
      size,
      rand,
      paint,
      phase,
      count: 16,
      radiusMin: 1.6,
      radiusRange: 3.0,
      driftAmp: 14.0,
      driftSpeed: 1.0,
      twinkleAmp: 0.2,
      twinkleSpeed: 1.6,
      baseAlpha: 0.08,
      color: accentColor,
    );

    // Near layer: largest, fastest drift, brightest twinkle, soft halo.
    _drawLayer(
      canvas,
      size,
      rand,
      paint,
      phase,
      count: 9,
      radiusMin: 2.2,
      radiusRange: 3.5,
      driftAmp: 26.0,
      driftSpeed: 1.5,
      twinkleAmp: 0.35,
      twinkleSpeed: 2.4,
      baseAlpha: 0.12,
      color: accentColor,
      halo: true,
    );
  }

  void _drawLayer(
    Canvas canvas,
    Size size,
    math.Random rand,
    Paint paint,
    double phase, {
    required int count,
    required double radiusMin,
    required double radiusRange,
    required double driftAmp,
    required double driftSpeed,
    required double twinkleAmp,
    required double twinkleSpeed,
    required double baseAlpha,
    required Color color,
    bool halo = false,
  }) {
    for (int i = 0; i < count; i++) {
      final baseX = rand.nextDouble() * size.width;
      final baseY = rand.nextDouble() * size.height;
      final r = radiusMin + rand.nextDouble() * radiusRange;
      final seed = rand.nextDouble() * math.pi * 2;

      // Lissajous-ish drift (decorrelated axes) so each mote wanders uniquely.
      final dx = baseX + math.sin(phase * driftSpeed + seed) * driftAmp;
      final dy = baseY +
          math.cos(phase * driftSpeed * 0.8 + seed * 1.3) * driftAmp * 0.6;

      final twinkle = 0.5 + 0.5 * math.sin(phase * twinkleSpeed + seed * 2.0);
      final alpha = (baseAlpha + twinkleAmp * twinkle).clamp(0.0, 0.6);

      if (halo) {
        final haloPaint = Paint()
          ..color = color.withValues(alpha: alpha * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(dx, dy), r * 1.7, haloPaint);
      }

      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientDustPainter oldDelegate) =>
      t != oldDelegate.t || accentColor != oldDelegate.accentColor;
}

/// Soft echoing orbs trailing the ghost as it flies away.
class _FlyAwayTrailPainter extends CustomPainter {
  final double progress;
  final double dy;
  final double dx;
  final double tilt;
  final double scale;
  final Color accent;

  _FlyAwayTrailPainter({
    required this.progress,
    required this.dy,
    required this.dx,
    required this.tilt,
    required this.scale,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const steps = 6;
    for (int i = steps; i >= 1; i--) {
      final f = i / steps;
      // Trail lags behind the current position.
      final ty = dy * (1 - f * 0.5);
      final tx = dx * (1 - f * 0.3);
      final s = (scale + f * 0.08).clamp(0.1, 1.2);
      final alpha = (1.0 - f) * 0.22 * (1.0 - progress);

      final paint = Paint()
        ..color =
            const Color(0xFFD8B4F8).withValues(alpha: alpha.clamp(0.0, 0.25))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(
        Offset(size.width / 2 + tx, size.height / 2 + ty),
        36 * s,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FlyAwayTrailPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

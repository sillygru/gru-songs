import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/database_service.dart';
import '../../services/sleep_timer_service.dart';
import '../screens/song_list_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/artists_screen.dart';
import '../screens/albums_screen.dart';
import '../screens/session_history_screen.dart';
import '../screens/queue_history_screen.dart';

class AppDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const AppDrawer({
    super.key,
    required this.onClose,
  });

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer>
    with SingleTickerProviderStateMixin {
  static const _panelRadius = BorderRadius.only(
    topRight: Radius.circular(34),
    bottomRight: Radius.circular(34),
  );

  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  Color _scrimColor1 = Colors.black;
  Color _scrimColor2 = Colors.black;
  Color _surfaceColor = Colors.black;
  Color _surfaceContainerHigh = Colors.black;
  Color _surfaceContainerLowest = Colors.black;
  Color _primaryColor = Colors.black;
  Color _shadowColor = Colors.black;
  Color _surfaceContainerHighest = Colors.black;
  Color _onSurface = Colors.black;
  Color _onSurfaceVariant = Colors.black;
  Color _primaryContainer = Colors.black;

  LinearGradient? _scrimGradient;
  LinearGradient? _backgroundGradient;
  RadialGradient? _topGlow;
  RadialGradient? _bottomGlow;
  LinearGradient? _headerGradient;
  LinearGradient? _iconBgGradient;
  LinearGradient? _navItemGradient;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    ));

    _controller.forward();
  }

  void _initColors(ColorScheme colorScheme) {
    _scrimColor1 = Colors.black.withValues(alpha: 0.36);
    _scrimColor2 = Colors.black.withValues(alpha: 0.58);
    _surfaceColor = colorScheme.surface.withValues(alpha: 0.78);
    _surfaceContainerHigh =
        colorScheme.surfaceContainerHigh.withValues(alpha: 0.7);
    _surfaceContainerLowest =
        colorScheme.surfaceContainerLowest.withValues(alpha: 0.64);
    _primaryColor = colorScheme.primary;
    _shadowColor = Colors.black.withValues(alpha: 0.22);
    _surfaceContainerHighest = colorScheme.surfaceContainerHighest;
    _onSurface = colorScheme.onSurface;
    _onSurfaceVariant = colorScheme.onSurfaceVariant;
    _primaryContainer = colorScheme.primaryContainer;

    _scrimGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [_scrimColor1, _scrimColor2],
    );

    _backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _surfaceColor,
        _surfaceContainerHigh,
        _surfaceContainerLowest,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    _topGlow = RadialGradient(
      colors: [
        _primaryColor.withValues(alpha: 0.26),
        _primaryColor.withValues(alpha: 0.0),
      ],
    );

    _bottomGlow = const RadialGradient(
      colors: [
        Color(0x3390CAF9),
        Color(0x00000000),
      ],
    );

    _headerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _surfaceContainerHighest.withValues(alpha: 0.5),
        _surfaceColor.withValues(alpha: 0.3),
      ],
    );

    _iconBgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _primaryContainer.withValues(alpha: 0.5),
        _primaryColor.withValues(alpha: 0.18),
      ],
    );

    _navItemGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _surfaceContainerHighest.withValues(alpha: 0.5),
        _surfaceContainerHighest.withValues(alpha: 0.2),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _closeDrawer() async {
    await _controller.reverse();
    widget.onClose();
  }

  void _navigateTo(Widget screen) {
    _closeDrawer().then((_) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_scrimColor1 == Colors.black) {
      _initColors(colorScheme);
    }

    final songCount = ref.watch(songsProvider.select((s) => s.when(
          data: (songs) => songs.length,
          loading: () => 0,
          error: (_, __) => 0,
        )));

    final BoxDecoration panelDecoration = BoxDecoration(
      borderRadius: _panelRadius,
      gradient: _backgroundGradient,
      boxShadow: [
        BoxShadow(
          color: _shadowColor,
          blurRadius: 36,
          offset: const Offset(10, 0),
        ),
      ],
    );

    final BoxDecoration topGlowDecoration = BoxDecoration(
      shape: BoxShape.circle,
      gradient: _topGlow,
    );

    final BoxDecoration bottomGlowDecoration = BoxDecoration(
      shape: BoxShape.circle,
      gradient: _bottomGlow,
    );

    final LinearGradient overlayGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _surfaceColor.withValues(alpha: 0.3),
        _surfaceColor.withValues(alpha: 0.1),
        _surfaceContainerHighest.withValues(alpha: 0.1),
      ],
    );

    return Stack(
      children: [
        GestureDetector(
          onTap: _closeDrawer,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              decoration: BoxDecoration(
                gradient: _scrimGradient,
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.8,
              child: Transform.translate(
                offset: Offset(
                  _slideAnimation.value *
                      MediaQuery.of(context).size.width *
                      0.8,
                  0,
                ),
                child: child,
              ),
            );
          },
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: _panelRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: panelDecoration,
                  child: Stack(
                    children: [
                      Positioned(
                        left: -56,
                        top: -16,
                        child: IgnorePointer(
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: topGlowDecoration,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -48,
                        bottom: 88,
                        child: IgnorePointer(
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: bottomGlowDecoration,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: overlayGradient,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: Container(
                              height: 1.2,
                              color: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: Container(
                              width: 1.2,
                              color: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, colorScheme, songCount),
                            const SizedBox(height: 8),
                            Expanded(
                              child: FadeTransition(
                                opacity: _fadeAnimation,
                                child: ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 0, 14, 18),
                                  children: [
                                    _buildSectionTitle(
                                      context,
                                      'Library',
                                      'Pinned shortcuts',
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.favorite_rounded,
                                      label: 'Favorites',
                                      subtitle: 'Your liked tracks',
                                      color: Colors.redAccent,
                                      onTap: () async {
                                        final songs = await ref
                                            .read(songsProvider.future);
                                        final userDataState =
                                            ref.read(userDataProvider);
                                        final favSongs = songs
                                            .where((s) => userDataState
                                                .isFavorite(s.filename))
                                            .toList();
                                        if (context.mounted) {
                                          _navigateTo(SongListScreen(
                                            title: 'Favorites',
                                            songs: favSongs,
                                          ));
                                        }
                                      },
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.queue_music_rounded,
                                      label: 'Playlists',
                                      subtitle: 'Curated sets',
                                      color: colorScheme.primary,
                                      onTap: () =>
                                          _navigateTo(const PlaylistsScreen()),
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.album_rounded,
                                      label: 'Albums',
                                      subtitle: 'Browse releases',
                                      color: Colors.orangeAccent,
                                      onTap: () =>
                                          _navigateTo(const AlbumsScreen()),
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.person_rounded,
                                      label: 'Artists',
                                      subtitle: 'Jump by artist',
                                      color: Colors.greenAccent,
                                      onTap: () =>
                                          _navigateTo(const ArtistsScreen()),
                                    ),
                                    const SizedBox(height: 14),
                                    _buildSectionTitle(
                                      context,
                                      'History',
                                      'Recent activity',
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.history_rounded,
                                      label: 'Song History',
                                      subtitle: 'What has been playing',
                                      color: Colors.purpleAccent,
                                      onTap: () => _navigateTo(
                                        const PlayHistoryScreen(),
                                      ),
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.queue_play_next,
                                      label: 'Session History',
                                      subtitle: 'Previous listening sessions',
                                      color: Colors.tealAccent,
                                      onTap: () => _navigateTo(
                                        const SessionHistoryScreen(),
                                      ),
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.queue_music_rounded,
                                      label: 'Queue History',
                                      subtitle: 'Past queues and order',
                                      color: Colors.amberAccent,
                                      onTap: () => _navigateTo(
                                        const QueueHistoryScreen(),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    _buildSectionTitle(
                                      context,
                                      'Tools',
                                      'Playback utility',
                                    ),
                                    _buildNavItem(
                                      context,
                                      icon: Icons.bedtime_rounded,
                                      label: 'Sleep Timer',
                                      subtitle: 'Stop playback gracefully',
                                      color: Colors.indigoAccent,
                                      onTap: () =>
                                          _navigateTo(const SleepTimerScreen()),
                                    ),
                                  ],
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
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
      BuildContext context, ColorScheme colorScheme, int songCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: _headerGradient,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: _iconBgGradient,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 64,
                          height: 64,
                          color: _primaryColor.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.music_note,
                            color: _primaryColor,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: _surfaceContainerHighest,
                  ),
                  child: IconButton(
                    onPressed: _closeDrawer,
                    icon: const Icon(Icons.close),
                    color: _onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Wispie',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Library: $songCount songs',
              style: TextStyle(
                color: _onSurface.withValues(alpha: 0.72),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _primaryColor.withValues(alpha: 0.92),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.35,
              textBaseline: TextBaseline.alphabetic,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: _onSurface.withValues(alpha: 0.56),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final BoxDecoration navItemDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: _navItemGradient,
    );

    final LinearGradient iconGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color.withValues(alpha: 0.34),
        color.withValues(alpha: 0.14),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: navItemDecoration,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: iconGradient,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.2,
                            color: _onSurface.withValues(alpha: 0.94),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _onSurface.withValues(alpha: 0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: _onSurfaceVariant,
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

// ============================================================================
// SLEEP TIMER SCREEN
// ============================================================================

class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  SleepTimerMode _mode = SleepTimerMode.playForTime;
  int _minutes = 30;
  int _tracks = 5;
  bool _letCurrentFinish = true;

  // Start from 5 minutes, go to 120 minutes in 5-min increments
  final List<int> _minuteOptions =
      List.generate(24, (i) => (i + 1) * 5); // 5-120
  // Start from 1 track, go to 40 tracks
  final List<int> _trackOptions = List.generate(40, (i) => i + 1); // 1-40

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final currentSong = audioManager.currentSongNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep Timer'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModeSelector(colorScheme),
            const SizedBox(height: 32),
            if (_mode == SleepTimerMode.playForTime ||
                _mode == SleepTimerMode.loopCurrent)
              _buildTimeSelector(colorScheme),
            if (_mode == SleepTimerMode.stopAfterTracks)
              _buildTrackSelector(colorScheme),
            if (_mode == SleepTimerMode.stopAfterCurrent)
              _buildCurrentSongInfo(currentSong, colorScheme),
            const SizedBox(height: 24),
            if (_mode == SleepTimerMode.playForTime ||
                _mode == SleepTimerMode.loopCurrent)
              _buildFinishToggle(colorScheme),
            const SizedBox(height: 32),
            _buildActionButtons(colorScheme),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(ColorScheme colorScheme) {
    final modes = [
      (
        SleepTimerMode.loopCurrent,
        Icons.repeat_one,
        'Loop Current Song',
        'Repeat the current song for a set time'
      ),
      (
        SleepTimerMode.playForTime,
        Icons.timer,
        'Play for Time',
        'Stop after a specified duration'
      ),
      (
        SleepTimerMode.stopAfterCurrent,
        Icons.stop_circle,
        'Stop After Current',
        'Stop when the current song ends'
      ),
      (
        SleepTimerMode.stopAfterTracks,
        Icons.playlist_play,
        'Stop After Tracks',
        'Stop after playing X more songs'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timer Mode',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...modes.map((mode) => _buildModeCard(mode, colorScheme)),
      ],
    );
  }

  Widget _buildModeCard(
    (SleepTimerMode, IconData, String, String) mode,
    ColorScheme colorScheme,
  ) {
    final (modeValue, icon, title, subtitle) = mode;
    final isSelected = _mode == modeValue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 2 : 0,
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => setState(() => _mode = modeValue),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color:
                      isSelected ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Duration',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_minutes min',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _minuteOptions.length,
            itemBuilder: (context, index) {
              final minute = _minuteOptions[index];
              final isSelected = _minutes == minute;
              return GestureDetector(
                onTap: () => setState(() => _minutes = minute),
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$minute',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'min',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? colorScheme.onPrimary.withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrackSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Number of Tracks',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_tracks tracks',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _trackOptions.length,
            itemBuilder: (context, index) {
              final track = _trackOptions[index];
              final isSelected = _tracks == track;
              return GestureDetector(
                onTap: () => setState(() => _tracks = track),
                child: Container(
                  width: 56,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$track',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentSongInfo(Song? song, ColorScheme colorScheme) {
    if (song == null) {
      return Card(
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No song is currently playing',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Song',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              song.artist,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinishToggle(ColorScheme colorScheme) {
    return Card(
      child: SwitchListTile(
        title: const Text('Let current song finish'),
        subtitle: Text(
          _letCurrentFinish
              ? 'Wait for the current song to end before stopping'
              : 'Stop immediately when timer expires',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: _letCurrentFinish,
        onChanged: (value) => setState(() => _letCurrentFinish = value),
        secondary: Icon(
          _letCurrentFinish ? Icons.check_circle : Icons.stop,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _startTimer,
            icon: const Icon(Icons.play_arrow),
            label: const Text(
              'Start Timer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (SleepTimerService.instance.isActive)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () {
                SleepTimerService.instance.cancel();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sleep timer cancelled')),
                );
              },
              icon: const Icon(Icons.stop),
              label: const Text('Cancel Active Timer'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _startTimer() {
    final audioManager = ref.read(audioPlayerManagerProvider);

    SleepTimerService.instance.start(
      mode: _mode,
      minutes: _minutes,
      tracks: _tracks,
      letCurrentFinish: _letCurrentFinish,
      audioManager: audioManager,
      onComplete: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sleep timer finished')),
          );
        }
      },
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_getTimerConfirmationMessage()),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _getTimerConfirmationMessage() {
    switch (_mode) {
      case SleepTimerMode.loopCurrent:
        return 'Looping current song for $_minutes minutes';
      case SleepTimerMode.playForTime:
        return 'Music will stop in $_minutes minutes';
      case SleepTimerMode.stopAfterCurrent:
        return 'Will stop after current song ends';
      case SleepTimerMode.stopAfterTracks:
        return 'Will stop after $_tracks more songs';
    }
  }
}

// ============================================================================
// PLAY HISTORY SCREEN
// ============================================================================

class PlayHistoryScreen extends ConsumerStatefulWidget {
  const PlayHistoryScreen({super.key});

  @override
  ConsumerState<PlayHistoryScreen> createState() => _PlayHistoryScreenState();
}

class _PlayHistoryScreenState extends ConsumerState<PlayHistoryScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }

      // Create a mutable copy of events
      final events = List<Map<String, dynamic>>.from(
        await DatabaseService.instance.getAllPlayEvents(),
      );

      // Sort by timestamp descending
      events.sort((a, b) {
        final aTime = (a['timestamp'] as num?)?.toDouble() ?? 0;
        final bTime = (b['timestamp'] as num?)?.toDouble() ?? 0;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Song History'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  children: [
                    if (_events.isNotEmpty) _buildLegend(colorScheme),
                    Expanded(
                      child: _events.isEmpty
                          ? _buildEmptyState(colorScheme)
                          : _buildHistoryList(colorScheme, songsAsync),
                    ),
                  ],
                ),
    );
  }

  Widget _buildLegend(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(Icons.play_arrow, Colors.green, 'Listen'),
          _buildLegendItem(Icons.skip_next, Colors.orange, 'Skip'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No play history yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start listening to build your history',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    ColorScheme colorScheme,
    AsyncValue<List<Song>> songsAsync,
  ) {
    final songMap = songsAsync.when(
      data: (songs) => {for (var s in songs) s.filename: s},
      loading: () => <String, Song>{},
      error: (_, __) => <String, Song>{},
    );

    // Group events by date
    final groupedEvents = <String, List<Map<String, dynamic>>>{};
    for (final event in _events) {
      final timestamp = (event['timestamp'] as num?)?.toDouble() ?? 0;
      final date =
          DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      groupedEvents.putIfAbsent(dateKey, () => []).add(event);
    }

    final sortedDates = groupedEvents.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final dateKey = sortedDates[index];
          final dateEvents = groupedEvents[dateKey]!;
          return _buildDateSection(dateKey, dateEvents, songMap, colorScheme);
        },
      ),
    );
  }

  Widget _buildDateSection(
    String dateKey,
    List<Map<String, dynamic>> events,
    Map<String, Song> songMap,
    ColorScheme colorScheme,
  ) {
    final parts = dateKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final date = DateTime(year, month, day);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String dateLabel;
    if (date == today) {
      dateLabel = 'Today';
    } else if (date == yesterday) {
      dateLabel = 'Yesterday';
    } else {
      dateLabel = _formatDate(date);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${events.length} plays',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...events
            .map((event) => _buildHistoryItem(event, songMap, colorScheme)),
      ],
    );
  }

  Widget _buildHistoryItem(
    Map<String, dynamic> event,
    Map<String, Song> songMap,
    ColorScheme colorScheme,
  ) {
    final filename = event['song_filename'] as String? ?? 'Unknown';
    final song = songMap[filename];
    final timestamp = (event['timestamp'] as num?)?.toDouble() ?? 0;
    final date =
        DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    final duration = (event['duration_played'] as num?)?.toDouble() ?? 0;
    final totalLength = (event['total_length'] as num?)?.toDouble() ?? 0;
    final ratio = totalLength > 0 ? duration / totalLength : 0.0;
    final isSkip = duration < 10 && ratio < 0.25;

    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final statusColor = isSkip ? Colors.orange : Colors.green;
    final statusIcon = isSkip ? Icons.skip_next : Icons.play_arrow;
    final statusText = isSkip ? 'Skip' : 'Listen';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: Text(
        song?.title ?? _getFileNameWithoutExt(filename),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        song?.artist ?? 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}m ${secs}s';
  }

  String _getFileNameWithoutExt(String filename) {
    final idx = filename.lastIndexOf('.');
    if (idx == -1) return filename;
    final name = filename.substring(0, idx);
    final sepIdx = name.lastIndexOf('/');
    if (sepIdx == -1) return name;
    return name.substring(sepIdx + 1);
  }
}

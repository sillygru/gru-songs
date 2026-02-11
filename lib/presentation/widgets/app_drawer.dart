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
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _controller.forward();
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
    final songsAsync = ref.watch(songsProvider);
    final userData = ref.watch(userDataProvider);

    return GestureDetector(
      onTap: _closeDrawer,
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {},
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.85,
                child: Transform.translate(
                  offset: Offset(
                    _slideAnimation.value *
                        MediaQuery.of(context).size.width *
                        0.85,
                    0,
                  ),
                  child: child,
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(4, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, colorScheme),
                    Expanded(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            _buildSectionTitle(context, 'Library'),
                            _buildNavItem(
                              context,
                              icon: Icons.favorite_rounded,
                              label: 'Favorites',
                              color: Colors.red,
                              onTap: () {
                                songsAsync.when(
                                  data: (songs) {
                                    final favSongs = songs
                                        .where((s) =>
                                            userData.isFavorite(s.filename))
                                        .toList();
                                    _navigateTo(SongListScreen(
                                      title: 'Favorites',
                                      songs: favSongs,
                                    ));
                                  },
                                  loading: () {},
                                  error: (_, __) {},
                                );
                              },
                            ),
                            _buildNavItem(
                              context,
                              icon: Icons.queue_music_rounded,
                              label: 'Playlists',
                              color: colorScheme.primary,
                              onTap: () => _navigateTo(const PlaylistsScreen()),
                            ),
                            _buildNavItem(
                              context,
                              icon: Icons.album_rounded,
                              label: 'Albums',
                              color: Colors.orange,
                              onTap: () => _navigateTo(const AlbumsScreen()),
                            ),
                            _buildNavItem(
                              context,
                              icon: Icons.person_rounded,
                              label: 'Artists',
                              color: Colors.green,
                              onTap: () => _navigateTo(const ArtistsScreen()),
                            ),
                            const Divider(
                                height: 32, indent: 16, endIndent: 16),
                            _buildSectionTitle(context, 'History'),
                            _buildNavItem(
                              context,
                              icon: Icons.history_rounded,
                              label: 'Song History',
                              color: Colors.purple,
                              onTap: () =>
                                  _navigateTo(const PlayHistoryScreen()),
                            ),
                            const Divider(
                                height: 32, indent: 16, endIndent: 16),
                            _buildSectionTitle(context, 'Tools'),
                            _buildNavItem(
                              context,
                              icon: Icons.bedtime_rounded,
                              label: 'Sleep Timer',
                              color: Colors.indigo,
                              onTap: () =>
                                  _navigateTo(const SleepTimerScreen()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/app_icon.png',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: colorScheme.primary,
                  child: Icon(Icons.music_note, color: colorScheme.onPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wispie',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _closeDrawer,
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.5),
      ),
      onTap: onTap,
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
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

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

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
          _buildLegendItem(Icons.play_arrow, colorScheme.primary, 'Listen'),
          _buildLegendItem(Icons.check_circle, Colors.green, 'Completed'),
          _buildLegendItem(Icons.skip_next, Colors.orange, 'Skipped'),
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
    final eventType = event['event_type'] as String? ?? 'listen';

    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    IconData eventIcon;
    Color eventColor;
    switch (eventType) {
      case 'complete':
        eventIcon = Icons.check_circle;
        eventColor = Colors.green;
        break;
      case 'skip':
        eventIcon = Icons.skip_next;
        eventColor = Colors.orange;
        break;
      default:
        eventIcon = Icons.play_arrow;
        eventColor = colorScheme.primary;
    }

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: eventColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(eventIcon, color: eventColor, size: 20),
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
            _formatDuration(duration),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
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

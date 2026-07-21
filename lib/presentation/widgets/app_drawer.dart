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
import '../screens/settings_screen.dart';
import 'album_art_image.dart';
import '../routes/player_route.dart';
import '../screens/unified_player_screen.dart';
import '../components/app_feedback.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../components/app_section_header.dart';
import '../components/app_surface.dart';
import '../tokens/app_tokens.dart';

/// The slide-out navigation panel.
///
/// It used to carry nine cached gradients, a blur, a drop shadow and a
/// different accent colour per row. All of that is gone: the panel is one flat
/// surface and the rows are [AppListRow]s, so it looks like the screens it
/// navigates to.
class AppDrawer extends ConsumerStatefulWidget {
  final Future<void> Function() onClose;
  final double drawerPosition;

  const AppDrawer({
    super.key,
    required this.onClose,
    required this.drawerPosition,
  });

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  static const _panelRadius = BorderRadius.only(
    topRight: Radius.circular(AppTokens.rLg),
    bottomRight: Radius.circular(AppTokens.rLg),
  );

  Future<void> _closeDrawer() async {
    await widget.onClose();
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

  /// Queue history lives inside the unified player's Queue pane, so this opens
  /// the player straight onto that segment rather than a standalone screen.
  void _openQueueHistory() {
    _closeDrawer().then((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        PlayerPageRoute(
          initialPane: PlayerPane.queue,
          queueShowsHistory: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTokens.accentOf(context, ref);

    final songCount = ref.watch(songsProvider.select((s) => s.when(
          data: (songs) => songs.length,
          loading: () => 0,
          error: (_, __) => 0,
        )));
    final updateAvailable = ref.watch(
      updateCheckProvider.select((state) => state.hasUpdate),
    );

    // Entrance: slide in from the left and fade up as the panel is revealed.
    final animationValue = widget.drawerPosition;
    final slideInOffset = (1.0 - animationValue) * -40.0;

    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: 0.8,
      child: RepaintBoundary(
        child: Transform.translate(
          offset: Offset(slideInOffset, 0),
          child: Opacity(
            opacity: animationValue.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  AppTokens.surface(1),
                  Theme.of(context).scaffoldBackgroundColor,
                ),
                borderRadius: _panelRadius,
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, accent, songCount),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.s3,
                          0,
                          AppTokens.s3,
                          AppTokens.s5,
                        ),
                        children: [
                          const AppSectionHeader(
                            label: 'Library',
                            padding: EdgeInsets.fromLTRB(
                              AppTokens.s3,
                              AppTokens.s3,
                              AppTokens.s3,
                              AppTokens.s1,
                            ),
                          ),
                          _buildNavItem(
                            icon: Icons.favorite_rounded,
                            label: 'Favorites',
                            subtitle: 'Your liked tracks',
                            color: AppTokens.danger,
                            onTap: () async {
                              final songs =
                                  await ref.read(songsProvider.future);
                              final userDataState = ref.read(userDataProvider);
                              final favSongs = songs
                                  .where((s) =>
                                      userDataState.isFavorite(s.filename))
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
                            icon: Icons.queue_music_rounded,
                            label: 'Playlists',
                            subtitle: 'Curated sets',
                            color: accent,
                            onTap: () => _navigateTo(const PlaylistsScreen()),
                          ),
                          _buildNavItem(
                            icon: Icons.album_rounded,
                            label: 'Albums',
                            subtitle: 'Browse releases',
                            color: accent,
                            onTap: () => _navigateTo(const AlbumsScreen()),
                          ),
                          _buildNavItem(
                            icon: Icons.person_rounded,
                            label: 'Artists',
                            subtitle: 'Jump by artist',
                            color: accent,
                            onTap: () => _navigateTo(const ArtistsScreen()),
                          ),
                          const AppSectionHeader(
                            label: 'History',
                            padding: EdgeInsets.fromLTRB(
                              AppTokens.s3,
                              AppTokens.s5,
                              AppTokens.s3,
                              AppTokens.s1,
                            ),
                          ),
                          _buildNavItem(
                            icon: Icons.history_rounded,
                            label: 'Song History',
                            subtitle: 'What has been playing',
                            color: accent,
                            onTap: () => _navigateTo(const PlayHistoryScreen()),
                          ),
                          _buildNavItem(
                            icon: Icons.queue_play_next_rounded,
                            label: 'Session History',
                            subtitle: 'Previous listening sessions',
                            color: accent,
                            onTap: () =>
                                _navigateTo(const SessionHistoryScreen()),
                          ),
                          _buildNavItem(
                            icon: Icons.queue_music_rounded,
                            label: 'Queue History',
                            subtitle: 'Past queues and order',
                            color: accent,
                            onTap: _openQueueHistory,
                          ),
                          const AppSectionHeader(
                            label: 'Tools',
                            padding: EdgeInsets.fromLTRB(
                              AppTokens.s3,
                              AppTokens.s5,
                              AppTokens.s3,
                              AppTokens.s1,
                            ),
                          ),
                          _buildNavItem(
                            icon: Icons.bedtime_rounded,
                            label: 'Sleep Timer',
                            subtitle: 'Stop playback gracefully',
                            color: accent,
                            onTap: () => _navigateTo(const SleepTimerScreen()),
                          ),
                          const AppSectionHeader(
                            label: 'App',
                            padding: EdgeInsets.fromLTRB(
                              AppTokens.s3,
                              AppTokens.s5,
                              AppTokens.s3,
                              AppTokens.s1,
                            ),
                          ),
                          _buildNavItem(
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            subtitle: 'Tune the app',
                            color: accent,
                            onTap: () => _navigateTo(const SettingsScreen()),
                            showBadge: updateAvailable,
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
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, int songCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s5,
        AppTokens.s3,
        AppTokens.s3,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppTokens.brSm,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Image.asset(
                'assets/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: accent.withValues(alpha: AppTokens.accentWashAlpha),
                  child:
                      Icon(Icons.music_note_rounded, color: accent, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Wispie', style: AppTokens.screenTitle(context)),
                const SizedBox(height: 2),
                Text(
                  '$songCount songs',
                  style: AppTokens.meta(context),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _closeDrawer,
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    bool showBadge = false,
  }) {
    return AppListRow(
      title: label,
      subtitle: subtitle,
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          AppRowIcon(icon: icon, color: color),
          if (showBadge)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTokens.danger,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppTokens.fgTertiary,
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
    final accent = AppTokens.accentOf(context, ref);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final currentSong = audioManager.currentSongNotifier.value;

    return Scaffold(
      appBar: const AppTopBar(title: 'Sleep Timer'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s4,
          0,
          AppTokens.s4,
          AppTokens.scrollBottomInset,
        ),
        children: [
          const AppSectionHeader(
            label: 'Timer Mode',
            padding: EdgeInsets.fromLTRB(
              AppTokens.s3,
              AppTokens.s3,
              AppTokens.s3,
              AppTokens.s2,
            ),
          ),
          _buildModeSelector(accent),
          if (_mode == SleepTimerMode.playForTime ||
              _mode == SleepTimerMode.loopCurrent) ...[
            _buildStepperSection(
              label: 'Duration',
              valueLabel: '$_minutes min',
              accent: accent,
              options: _minuteOptions,
              selected: _minutes,
              suffix: 'min',
              width: 62,
              onSelected: (value) => setState(() => _minutes = value),
            ),
            const SizedBox(height: AppTokens.s4),
            _buildFinishToggle(),
          ],
          if (_mode == SleepTimerMode.stopAfterTracks)
            _buildStepperSection(
              label: 'Number of Tracks',
              valueLabel: '$_tracks tracks',
              accent: accent,
              options: _trackOptions,
              selected: _tracks,
              width: 54,
              onSelected: (value) => setState(() => _tracks = value),
            ),
          if (_mode == SleepTimerMode.stopAfterCurrent)
            _buildCurrentSongInfo(currentSong),
          const SizedBox(height: AppTokens.s6),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildModeSelector(Color accent) {
    const modes = [
      (
        SleepTimerMode.loopCurrent,
        Icons.repeat_one_rounded,
        'Loop Current Song',
        'Repeat the current song for a set time'
      ),
      (
        SleepTimerMode.playForTime,
        Icons.timer_rounded,
        'Play for Time',
        'Stop after a specified duration'
      ),
      (
        SleepTimerMode.stopAfterCurrent,
        Icons.stop_circle_rounded,
        'Stop After Current',
        'Stop when the current song ends'
      ),
      (
        SleepTimerMode.stopAfterTracks,
        Icons.playlist_play_rounded,
        'Stop After Tracks',
        'Stop after playing X more songs'
      ),
    ];

    return AppSurfaceGroup(
      children: [
        for (final (modeValue, icon, title, subtitle) in modes)
          AppListRow(
            title: title,
            subtitle: subtitle,
            accent: accent,
            isActive: _mode == modeValue,
            leading: AppRowIcon(icon: icon, color: accent),
            onTap: () => setState(() => _mode = modeValue),
            trailing: _mode == modeValue
                ? Icon(Icons.check_circle_rounded, color: accent, size: 20)
                : null,
          ),
      ],
    );
  }

  /// Horizontal picker of pill options. Used by both the minutes and the
  /// tracks selector, which were previously two near-identical blocks.
  Widget _buildStepperSection({
    required String label,
    required String valueLabel,
    required Color accent,
    required List<int> options,
    required int selected,
    required double width,
    required ValueChanged<int> onSelected,
    String? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s3,
            AppTokens.s5,
            AppTokens.s3,
            AppTokens.s3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTokens.sectionLabel(context),
                ),
              ),
              Text(
                valueLabel,
                style: AppTokens.meta(context).copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = selected == option;

              return GestureDetector(
                onTap: () => onSelected(option),
                child: Container(
                  width: width,
                  margin: const EdgeInsets.only(right: AppTokens.s2),
                  decoration: BoxDecoration(
                    color: isSelected ? accent : AppTokens.surface(1),
                    borderRadius: AppTokens.brSm,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$option',
                        style: AppTokens.stat(context).copyWith(
                          fontSize: 18,
                          color: isSelected
                              ? AppTokens.onAccent(accent)
                              : Colors.white,
                        ),
                      ),
                      if (suffix != null)
                        Text(
                          suffix,
                          style: AppTokens.meta(context).copyWith(
                            color: isSelected
                                ? AppTokens.onAccent(accent)
                                    .withValues(alpha: 0.7)
                                : AppTokens.fgTertiary,
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

  Widget _buildCurrentSongInfo(Song? song) {
    if (song == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.s5),
        child: AppSurface(
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTokens.danger, size: 20),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Text(
                  'No song is currently playing',
                  style: AppTokens.rowSubtitle(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s5),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CURRENT SONG', style: AppTokens.sectionLabel(context)),
            const SizedBox(height: AppTokens.s2),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.rowTitle(context),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.rowSubtitle(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinishToggle() {
    return AppSurface(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s1),
      child: SwitchListTile(
        title: const Text('Let current song finish'),
        subtitle: Text(
          _letCurrentFinish
              ? 'Wait for the current song to end before stopping'
              : 'Stop immediately when timer expires',
        ),
        value: _letCurrentFinish,
        onChanged: (value) => setState(() => _letCurrentFinish = value),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _startTimer,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start Timer'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        if (SleepTimerService.instance.isActive) ...[
          const SizedBox(height: AppTokens.s3),
          OutlinedButton.icon(
            onPressed: () {
              SleepTimerService.instance.cancel();
              setState(() {});
              appSnack(context, 'Sleep timer cancelled');
            },
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Cancel Active Timer'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
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
          appSnack(context, 'Sleep timer finished', tone: AppTone.success);
        }
      },
    );

    Navigator.pop(context);
    appSnack(context, _getTimerConfirmationMessage(), tone: AppTone.success);
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
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Song History',
        actions: [
          IconButton(
            onPressed: _loadHistory,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const AppLoading()
          : _error != null
              ? AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load history',
                  message: _error,
                  tone: AppTone.danger,
                )
              : _events.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.history_rounded,
                      title: 'No play history yet',
                      message: 'Start listening to build your history.',
                    )
                  : Column(
                      children: [
                        _buildLegend(),
                        Expanded(child: _buildHistoryList(songsAsync)),
                      ],
                    ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.s3,
        horizontal: AppTokens.s5,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(
              Icons.play_arrow_rounded, AppTokens.success, 'Listen'),
          const SizedBox(width: AppTokens.s5),
          _buildLegendItem(Icons.skip_next_rounded, AppTokens.warning, 'Skip'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: AppTokens.s1),
        Text(
          label.toUpperCase(),
          style: AppTokens.sectionLabel(context).copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildHistoryList(AsyncValue<List<Song>> songsAsync) {
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
        padding: const EdgeInsets.only(
          bottom: AppTokens.scrollBottomInset,
        ),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final dateKey = sortedDates[index];
          return _buildDateSection(dateKey, groupedEvents[dateKey]!, songMap);
        },
      ),
    );
  }

  Widget _buildDateSection(
    String dateKey,
    List<Map<String, dynamic>> events,
    Map<String, Song> songMap,
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

    final totalSeconds = events.fold<int>(0, (sum, event) {
      final dur = (event['duration_played'] as num?)?.toDouble() ?? 0;
      return sum + dur.toInt();
    });
    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    String durationStr;
    if (hours > 0) {
      durationStr = '${hours}h ${mins}m';
    } else {
      durationStr = '${mins}m';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          label: dateLabel,
          actionLabel: '${events.length} plays · $durationStr',
        ),
        ...events.map((event) => _buildHistoryItem(event, songMap)),
      ],
    );
  }

  Widget _buildHistoryItem(
    Map<String, dynamic> event,
    Map<String, Song> songMap,
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

    final statusColor = isSkip ? AppTokens.warning : AppTokens.success;
    final statusText = isSkip ? 'Skip' : 'Listen';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
      child: AppListRow(
        leading: AppRowArt(
          child: AlbumArtImage(
            url: song?.coverUrl ?? '',
            width: AppTokens.artSize,
            height: AppTokens.artSize,
          ),
        ),
        title: song?.title ?? _getFileNameWithoutExt(filename),
        subtitle: song?.artist ?? 'Unknown Artist',
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeStr, style: AppTokens.meta(context)),
            const SizedBox(height: 2),
            Text(
              statusText.toUpperCase(),
              style: AppTokens.sectionLabel(context).copyWith(
                color: statusColor,
              ),
            ),
          ],
        ),
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

  String _getFileNameWithoutExt(String filename) {
    final idx = filename.lastIndexOf('.');
    if (idx == -1) return filename;
    final name = filename.substring(0, idx);
    final sepIdx = name.lastIndexOf('/');
    if (sepIdx == -1) return name;
    return name.substring(sepIdx + 1);
  }
}

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/screen_wake_lock_service.dart';
import '../widgets/lyrics_line.dart';
import '../widgets/blurred_background.dart';

class FullScreenLyrics extends ConsumerStatefulWidget {
  final String songId;
  final String songTitle;
  final String songArtist;
  final List<LyricLine> lyrics;
  final Color? extractedColor;
  final Duration? initialPosition;

  const FullScreenLyrics({
    super.key,
    required this.songId,
    required this.songTitle,
    required this.songArtist,
    required this.lyrics,
    this.extractedColor,
    this.initialPosition,
  });

  @override
  ConsumerState<FullScreenLyrics> createState() => _FullScreenLyricsState();
}

class _FullScreenLyricsState extends ConsumerState<FullScreenLyrics> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(-1);
  final Map<int, GlobalKey> _lineKeys = {};

  bool _autoScrollEnabled = true;
  bool _isAutoScrolling = false;
  bool _isUserInteracting = false;
  bool _isTransitioningSong = false;
  int _currentLyricIndex = -1;
  Duration _lastKnownPlayerPosition = Duration.zero;
  DateTime _lastAutoScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUserInteractionAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _autoResumeTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<SequenceState?>? _sequenceSubscription;
  Timer? _positionPollTimer;
  double _dismissOverscrollAccumulator = 0;
  ProviderSubscription<SettingsState>? _settingsSubscription;
  bool _lyricsWakeLockHeld = false;

  late String _activeSongId;
  late List<LyricLine> _activeLyrics;

  AudioPlayer get player => ref.read(audioPlayerManagerProvider).player;

  static const double _lyricFontSize = 29.0;
  static const double _syncResumeDistanceThreshold = 180.0;
  static const Duration _scrollAnimationDuration = Duration(milliseconds: 460);
  static const Duration _scrollCooldown = Duration(milliseconds: 280);
  static const Duration _seekDetectionWindow = Duration(milliseconds: 900);
  static const Duration _positionLookAhead = Duration(milliseconds: 140);
  static const Duration _autoResumeDelay = Duration(seconds: 3);
  static const Duration _autoResumeSnapDuration = Duration(milliseconds: 120);
  static const Duration _positionPollInterval = Duration(milliseconds: 120);
  static const double _dismissOverscrollThreshold = 80;
  static const double _upcomingBlurSigma = 2.2;
  static const double _manualModeUpcomingBlurSigma = 1.0;
  static const double _defaultSmallBlurSigma = 1.0;

  @override
  void initState() {
    super.initState();
    _activeSongId = widget.songId;
    _activeLyrics = List<LyricLine>.from(widget.lyrics);

    final initialPosition = widget.initialPosition ?? player.position;
    _lastKnownPlayerPosition = initialPosition;
    if (_activeLyrics.isNotEmpty) {
      final initialIndex =
          _findLyricIndexAt(initialPosition + _positionLookAhead);
      if (initialIndex >= 0) {
        _currentLyricIndex = initialIndex;
        _currentIndexNotifier.value = initialIndex;
      }
    }

    _setupPositionListener();
    _setupSequenceListener();
    _settingsSubscription = ref.listenManual<SettingsState>(
      settingsProvider,
      (_, __) => unawaited(_syncLyricsWakeLock()),
    );
    unawaited(_syncLyricsWakeLock());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncToCurrentPosition(forceScroll: true);
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _syncToCurrentPosition(forceScroll: true);
      });
    });
  }

  void _setupPositionListener() {
    _positionSubscription = player.positionStream.listen((position) {
      if (!mounted) return;
      _updateCurrentLyricIndex(position);
    });

    _positionPollTimer = Timer.periodic(_positionPollInterval, (_) {
      if (!mounted) return;
      _updateCurrentLyricIndex(player.position);
    });
  }

  void _setupSequenceListener() {
    _sequenceSubscription = player.sequenceStateStream.listen((state) {
      if (!mounted || _isTransitioningSong) return;
      final tag = state.currentSource?.tag;
      if (tag is! MediaItem || tag.id == _activeSongId) return;
      unawaited(_handleSongChange(tag.id));
    });
  }

  Future<void> _syncLyricsWakeLock() async {
    final shouldKeepAwake = ref.read(settingsProvider).keepScreenAwakeOnLyrics;
    if (shouldKeepAwake && !_lyricsWakeLockHeld) {
      _lyricsWakeLockHeld = true;
      await ScreenWakeLockService.instance.acquire('lyrics_screen');
    } else if (!shouldKeepAwake && _lyricsWakeLockHeld) {
      _lyricsWakeLockHeld = false;
      await ScreenWakeLockService.instance.release('lyrics_screen');
    }
  }

  Future<void> _handleSongChange(String newSongId) async {
    _isTransitioningSong = true;
    try {
      final songs = ref.read(songsProvider).asData?.value ?? const <Song>[];
      Song? nextSong;
      for (final song in songs) {
        if (song.filename == newSongId) {
          nextSong = song;
          break;
        }
      }
      if (!mounted) return;
      if (nextSong == null) {
        Navigator.of(context).maybePop();
        return;
      }

      final repo = ref.read(songRepositoryProvider);
      final lyricsContent = await repo.getLyrics(nextSong);
      if (!mounted) return;

      final parsedLyrics = lyricsContent == null
          ? const <LyricLine>[]
          : LyricLine.parse(lyricsContent);
      if (parsedLyrics.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _lineKeys.clear();
      _dismissOverscrollAccumulator = 0;
      _lastKnownPlayerPosition = player.position;

      setState(() {
        _activeSongId = nextSong!.filename;
        _activeLyrics = parsedLyrics;
        _autoScrollEnabled = true;
        _isUserInteracting = false;
        _currentLyricIndex = -1;
        _currentIndexNotifier.value = -1;
      });

      _syncToCurrentPosition(forceScroll: true);
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _syncToCurrentPosition(forceScroll: true);
      });
    } finally {
      _isTransitioningSong = false;
    }
  }

  void _updateCurrentLyricIndex(Duration position) {
    if (_activeLyrics.isEmpty) return;
    final adjustedPosition = position + _positionLookAhead;
    final newIndex = _findLyricIndexAt(adjustedPosition);
    final positionDelta = position - _lastKnownPlayerPosition;
    final isLikelySeek = positionDelta.abs() > _seekDetectionWindow ||
        positionDelta < const Duration(milliseconds: -250);
    _lastKnownPlayerPosition = position;

    if (newIndex < 0) return;

    if (isLikelySeek && !_autoScrollEnabled && mounted) {
      setState(() => _autoScrollEnabled = true);
      _isUserInteracting = false;
      _autoResumeTimer?.cancel();
    }

    if (newIndex != _currentIndexNotifier.value) {
      _currentIndexNotifier.value = newIndex;
      setState(() => _currentLyricIndex = newIndex);

      if (_autoScrollEnabled) {
        if (isLikelySeek) {
          _scrollToCurrentLine(force: true);
        } else {
          _scheduleScroll();
        }
      }
    }
  }

  void _syncToCurrentPosition({bool forceScroll = false}) {
    _updateCurrentLyricIndex(player.position);
    if (_autoScrollEnabled) {
      _scrollToCurrentLine(force: forceScroll);
    }
  }

  int _findLyricIndexAt(Duration position) {
    int result = -1;
    for (int i = 0; i < _activeLyrics.length; i++) {
      final lineTime = _activeLyrics[i].time;
      if (!_activeLyrics[i].isSynced) continue;
      if (lineTime <= position) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }

  void _scheduleScroll() {
    final now = DateTime.now();
    final timeSinceLastScroll = now.difference(_lastAutoScrollAt);
    if (_isAutoScrolling || timeSinceLastScroll < _scrollCooldown) return;

    _lastAutoScrollAt = now;
    _scrollToCurrentLine();
  }

  Future<void> _scrollToCurrentLine({
    bool force = false,
    Duration? duration,
  }) async {
    if (!_scrollController.hasClients || _currentLyricIndex < 0) return;

    final targetOffset = _getTargetOffsetForIndex(_currentLyricIndex);
    if (targetOffset == null) return;

    final currentOffset = _scrollController.offset;
    final offsetDiff = (targetOffset - currentOffset).abs();
    if (!force && offsetDiff <= 6) return;

    if (force) {
      _scrollController.jumpTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
      return;
    }

    _isAutoScrolling = true;
    try {
      await _scrollController.animateTo(
        targetOffset,
        duration: duration ?? _scrollAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isAutoScrolling = false;
    }
  }

  void _checkReenableAutoScroll() {
    if (_isAutoScrolling ||
        _isUserInteracting ||
        _currentLyricIndex == -1 ||
        _autoScrollEnabled) {
      return;
    }

    final targetOffset = _getTargetOffsetForIndex(_currentLyricIndex);
    if (targetOffset == null) return;

    final currentOffset = _scrollController.offset;
    final distanceToTarget = (currentOffset - targetOffset).abs();

    if (distanceToTarget <= _syncResumeDistanceThreshold) {
      setState(() => _autoScrollEnabled = true);
      _scrollToCurrentLine(duration: _autoResumeSnapDuration);
    }
  }

  void _markUserInteraction() {
    _lastUserInteractionAt = DateTime.now();
    _isUserInteracting = true;
    _autoResumeTimer?.cancel();
    if (_autoScrollEnabled && mounted) {
      setState(() => _autoScrollEnabled = false);
    }
  }

  void _scheduleAutoResume() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = Timer(_autoResumeDelay, () {
      if (!mounted || _isUserInteracting || _autoScrollEnabled) return;
      final elapsed = DateTime.now().difference(_lastUserInteractionAt);
      if (elapsed < _autoResumeDelay) return;
      _checkReenableAutoScroll();
    });
  }

  double? _getTargetOffsetForIndex(int index) {
    if (!_scrollController.hasClients) return null;
    final key = _lineKeys[index];
    final maxScroll = _scrollController.position.maxScrollExtent;
    final context = key?.currentContext;
    if (context == null) {
      if (_activeLyrics.length <= 1) return 0;
      return (maxScroll * (index / (_activeLyrics.length - 1)))
          .clamp(0.0, maxScroll)
          .toDouble();
    }

    final renderObject = context.findRenderObject();
    if (renderObject == null) return null;

    final viewport = RenderAbstractViewport.of(renderObject);
    final reveal = viewport.getOffsetToReveal(renderObject, 0.4);
    return reveal.offset.clamp(0.0, maxScroll).toDouble();
  }

  void _seekToLyric(int index) {
    if (index < 0 || index >= _activeLyrics.length) return;
    if (!_activeLyrics[index].isSynced) return;
    final time = _activeLyrics[index].time;

    if (index != _currentIndexNotifier.value) {
      _currentIndexNotifier.value = index;
      setState(() => _currentLyricIndex = index);
    } else if (mounted) {
      setState(() {});
    }

    setState(() => _autoScrollEnabled = true);
    _isUserInteracting = false;
    _autoResumeTimer?.cancel();
    _lastKnownPlayerPosition = time;
    _lastAutoScrollAt = DateTime.now();
    _scrollToCurrentLine(force: true);
    player.seek(time);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _currentIndexNotifier.dispose();
    _autoResumeTimer?.cancel();
    _positionSubscription?.cancel();
    _positionPollTimer?.cancel();
    _sequenceSubscription?.cancel();
    _settingsSubscription?.close();
    if (_lyricsWakeLockHeld) {
      unawaited(ScreenWakeLockService.instance.release('lyrics_screen'));
      _lyricsWakeLockHeld = false;
    }
    super.dispose();
  }

  Color _getExtractedColor() {
    return widget.extractedColor ?? Colors.deepPurple;
  }

  @override
  Widget build(BuildContext context) {
    final extractedColor = _getExtractedColor();
    final hasTimedLyrics = _activeLyrics.any((l) => l.isSynced);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildBackgroundLayers(extractedColor),
          _buildContent(hasTimedLyrics),
        ],
      ),
    );
  }

  Widget _buildBackgroundLayers(Color extractedColor) {
    final songs = ref.watch(songsProvider).value ?? [];
    String url = '';
    try {
      final song = songs.firstWhere((s) => s.filename == _activeSongId);
      url = song.coverUrl ?? '';
    } catch (_) {
      // If not in our song list, try to find current media item
      final tag = player.sequenceState.currentSource?.tag;
      if (tag is MediaItem && tag.id == _activeSongId) {
        url = tag.artUri.toString();
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: BlurredBackground(
            key: ValueKey('bg_lyrics_$_activeSongId'),
            url: url,
            filename: _activeSongId,
            sigma: 25,
            gradientColors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.black.withValues(alpha: 0.8),
            ],
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  extractedColor.withValues(alpha: 0.16),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(bool hasTimedLyrics) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () => Navigator.pop(context),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: _activeLyrics.isEmpty
                      ? KeyedSubtree(
                          key: const ValueKey('lyrics-empty'),
                          child: _buildEmptyState(),
                        )
                      : KeyedSubtree(
                          key: ValueKey('lyrics$_activeSongId'),
                          child: _buildLyricsList(hasTimedLyrics),
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 12,
            child: _buildCloseButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
            color: Colors.white,
            onPressed: () => Navigator.pop(context),
            padding: const EdgeInsets.all(7),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lyrics_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'No lyrics available',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lyrics will appear here when available',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsList(bool hasTimedLyrics) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _handleScrollNotification(notification);
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(8, 88, 8, 136),
            itemCount: _activeLyrics.length,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemBuilder: (context, index) {
              final line = _activeLyrics[index];
              final hasTime = line.isSynced;
              final key = _lineKeys.putIfAbsent(
                index,
                () => GlobalKey(),
              );

              return ValueListenableBuilder<int>(
                valueListenable: _currentIndexNotifier,
                builder: (context, currentIndex, child) {
                  final isBeforeFirstTimedLine =
                      hasTimedLyrics && currentIndex < 0;
                  final isActive = hasTimedLyrics && index == currentIndex;
                  final isPlayed = currentIndex >= 0 && index <= currentIndex;
                  final blurSigma = !hasTimedLyrics || isBeforeFirstTimedLine
                      ? _defaultSmallBlurSigma
                      : (isPlayed
                          ? 0.0
                          : (_autoScrollEnabled
                              ? _upcomingBlurSigma
                              : _manualModeUpcomingBlurSigma));
                  return LyricsLine(
                    key: key,
                    text: line.text,
                    isActive: isActive,
                    isPlayed: isPlayed,
                    blurSigma: blurSigma,
                    hasTime: hasTime,
                    activeFontSize: _lyricFontSize,
                    inactiveFontSize: _lyricFontSize,
                    activeColor: Colors.white,
                    glowIntensity: isActive ? 1.0 : 0.0,
                    onTap: hasTimedLyrics ? () => _seekToLyric(index) : null,
                  );
                },
              );
            },
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 118,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.62),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 166,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (_isAutoScrolling) return;
    final isUserDriven = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      ScrollEndNotification(:final dragDetails) => dragDetails != null,
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      _ => false,
    };
    if (notification is OverscrollNotification) {
      if (isUserDriven &&
          notification.overscroll < 0 &&
          _scrollController.hasClients &&
          _scrollController.offset <= 0.5) {
        _dismissOverscrollAccumulator += -notification.overscroll;
        if (_dismissOverscrollAccumulator >= _dismissOverscrollThreshold) {
          Navigator.pop(context);
          return;
        }
      } else {
        _dismissOverscrollAccumulator = 0;
      }
      if (isUserDriven) {
        _markUserInteraction();
      }
    } else if (notification is ScrollStartNotification) {
      _dismissOverscrollAccumulator = 0;
      if (isUserDriven) {
        _markUserInteraction();
      }
    } else if (notification is ScrollUpdateNotification) {
      if (isUserDriven) {
        _markUserInteraction();
      }
    } else if (notification is UserScrollNotification) {
      if (isUserDriven) {
        _markUserInteraction();
      } else {
        _isUserInteracting = false;
        _dismissOverscrollAccumulator = 0;
        _scheduleAutoResume();
      }
    } else if (notification is ScrollEndNotification) {
      if (isUserDriven) {
        _isUserInteracting = false;
        _dismissOverscrollAccumulator = 0;
        _scheduleAutoResume();
      }
    }
  }
}

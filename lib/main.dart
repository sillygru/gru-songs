import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'models/song.dart';
import 'services/api_service.dart';
import 'services/audio_player_manager.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GruSongsApp());
}

class GruSongsApp extends StatelessWidget {
  const GruSongsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gru Songs',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ApiService _apiService = ApiService();
  final AudioPlayerManager _audioManager = AudioPlayerManager();
  late Future<List<Song>> _songsFuture;
  bool _isAudioInitialized = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _songsFuture = _apiService.fetchSongs();
    _songsFuture.then((songs) {
      if (_isAudioInitialized) {
        _audioManager.init(songs);
      }
    }).catchError((error) {
      debugPrint('Error fetching songs: $error');
    });
  }

  Future<void> _initAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sillygru.gru_songs.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    );
    setState(() {
      _isAudioInitialized = true;
    });
    // If songs loaded before audio init, initialize player now
    final songs = await _songsFuture;
    _audioManager.init(songs);
  }

  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gru Songs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _songsFuture = _apiService.fetchSongs();
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<Song>>(
            future: _songsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
                            } else if (snapshot.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SelectableText(
                                        'Error: ${snapshot.error}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.redAccent),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _songsFuture = _apiService.fetchSongs();
                                          });
                                        },
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
               else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No songs found'));
              }

              final songs = snapshot.data!;
              return ListView.builder(
                itemCount: songs.length,
                padding: const EdgeInsets.only(bottom: 80),
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: song.coverUrl != null 
                          ? ApiService.getFullUrl(song.coverUrl!) 
                          : ApiService.getFullUrl('/stream/cover.jpg'),
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.music_note),
                      ),
                    ),
                    title: Text(song.title),
                    subtitle: Text(song.artist),
                    onTap: () {
                      _audioManager.player.seek(Duration.zero, index: index);
                      _audioManager.player.play();
                    },
                  );
                },
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NowPlayingBar(player: _audioManager.player),
          ),
        ],
      ),
    );
  }
}

class NowPlayingBar extends StatelessWidget {
  final AudioPlayer player;

  const NowPlayingBar({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();

        final metadata = state.currentSource?.tag as MediaItem?;
        if (metadata == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => NowPlayingScreen(player: player),
            );
          },
          child: Container(
            height: 70,
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: metadata.artUri.toString(),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        metadata.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final playing = playerState?.playing ?? false;
                    final processingState = playerState?.processingState;

                    if (processingState == ProcessingState.buffering) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }

                    return IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playing ? player.pause : player.play,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: player.hasNext ? player.seekToNext : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class NowPlayingScreen extends StatefulWidget {
  final AudioPlayer player;

  const NowPlayingScreen({super.key, required this.player});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;
  List<LyricLine>? _lyrics;
  bool _loadingLyrics = false;
  String? _lastSongId;
  final ScrollController _lyricsScrollController = ScrollController();
  int _currentLyricIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.player.sequenceStateStream.listen((state) {
      final metadata = state?.currentSource?.tag as MediaItem?;
      if (metadata?.id != _lastSongId) {
        if (mounted) {
          setState(() {
            _lastSongId = metadata?.id;
            _lyrics = null;
            _showLyrics = false;
            _loadingLyrics = false;
            _currentLyricIndex = -1;
          });
        }
      }
    });

    widget.player.positionStream.listen((position) {
      if (_lyrics != null && _showLyrics) {
        int newIndex = -1;
        for (int i = 0; i < _lyrics!.length; i++) {
          if (_lyrics![i].time <= position) {
            newIndex = i;
          } else {
            break;
          }
        }

        if (newIndex != _currentLyricIndex && newIndex != -1) {
          setState(() {
            _currentLyricIndex = newIndex;
          });
          _scrollToCurrentLyric();
        }
      }
    });
  }

  void _scrollToCurrentLyric() {
    if (_lyricsScrollController.hasClients && _currentLyricIndex != -1) {
      _lyricsScrollController.animateTo(
        _currentLyricIndex * 40.0, // Estimated height per line
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _toggleLyrics(String? lyricsUrl) async {
    if (_showLyrics) {
      setState(() => _showLyrics = false);
      return;
    }

    if (lyricsUrl == null) return;

    setState(() {
      _showLyrics = true;
      if (_lyrics == null) _loadingLyrics = true;
    });

    if (_lyrics == null) {
      final lyricsContent = await ApiService().fetchLyrics(lyricsUrl);
      if (mounted) {
        setState(() {
          _lyrics = lyricsContent != null ? LyricLine.parse(lyricsContent) : [];
          _loadingLyrics = false;
        });
      }
    }
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          widget.player.positionStream,
          widget.player.bufferedPositionStream,
          widget.player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: StreamBuilder<SequenceState?>(
        stream: widget.player.sequenceStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final metadata = state?.currentSource?.tag as MediaItem?;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
              if (metadata != null) ...[
                if (!_showLyrics)
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: metadata.artUri.toString(),
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 100),
                      ),
                    ),
                  )
                else
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _loadingLyrics
                          ? const Center(child: CircularProgressIndicator())
                          : (_lyrics == null || _lyrics!.isEmpty)
                              ? const Center(child: Text('No lyrics available'))
                              : ListView.builder(
                                  controller: _lyricsScrollController,
                                  itemCount: _lyrics!.length,
                                  itemBuilder: (context, index) {
                                    final isCurrent = index == _currentLyricIndex;
                                    return Container(
                                      height: 40,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Text(
                                        _lyrics![index].text,
                                        style: TextStyle(
                                          fontSize: isCurrent ? 20 : 16,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                          color: isCurrent ? Colors.white : Colors.grey[500],
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  metadata.title,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${metadata.artist ?? 'Unknown Artist'} • ${metadata.album ?? 'Unknown Album'}',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 32),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return ProgressBar(
                    progress: positionData?.position ?? Duration.zero,
                    buffered: positionData?.bufferedPosition ?? Duration.zero,
                    total: positionData?.duration ?? Duration.zero,
                    onSeek: widget.player.seek,
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  StreamBuilder<bool>(
                    stream: widget.player.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final shuffleModeEnabled = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(Icons.shuffle, color: shuffleModeEnabled ? Colors.deepPurple : Colors.white),
                        onPressed: () => widget.player.setShuffleModeEnabled(!shuffleModeEnabled),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 36),
                    onPressed: widget.player.hasPrevious ? widget.player.seekToPrevious : null,
                  ),
                  StreamBuilder<PlayerState>(
                    stream: widget.player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? false;
                      return IconButton(
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 72),
                        onPressed: playing ? widget.player.pause : widget.player.play,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 36),
                    onPressed: widget.player.hasNext ? widget.player.seekToNext : null,
                  ),
                  StreamBuilder<LoopMode>(
                    stream: widget.player.loopModeStream,
                    builder: (context, snapshot) {
                      final loopMode = snapshot.data ?? LoopMode.off;
                      const icons = {
                        LoopMode.off: Icon(Icons.repeat, color: Colors.white),
                        LoopMode.one: Icon(Icons.repeat_one, color: Colors.deepPurple),
                        LoopMode.all: Icon(Icons.repeat, color: Colors.deepPurple),
                      };
                      return IconButton(
                        icon: icons[loopMode]!,
                        onPressed: () {
                          final nextMode = LoopMode.values[(loopMode.index + 1) % LoopMode.values.length];
                          widget.player.setLoopMode(nextMode);
                        },
                      );
                    },
                  ),
                  // Lyrics toggle button if lyrics available
                  if (metadata?.extras?['lyricsUrl'] != null)
                    IconButton(
                      icon: const Icon(Icons.lyrics),
                      color: _showLyrics ? Colors.deepPurple : Colors.white,
                      onPressed: () => _toggleLyrics(metadata!.extras!['lyricsUrl'] as String),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}
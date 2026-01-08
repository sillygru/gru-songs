import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showLyrics = false;
  List<LyricLine>? _lyrics;
  bool _loadingLyrics = false;
  String? _lastSongId;
  final ScrollController _lyricsScrollController = ScrollController();
  int _currentLyricIndex = -1;

  AudioPlayer get player => ref.read(audioPlayerManagerProvider).player;

  @override
  void initState() {
    super.initState();
    player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      final String? songId = tag is MediaItem ? tag.id : null;
      
      if (songId != _lastSongId) {
        if (mounted) {
          setState(() {
            _lastSongId = songId;
            _lyrics = null;
            _showLyrics = false;
            _loadingLyrics = false;
            _currentLyricIndex = -1;
          });
        }
      }
    });

    player.positionStream.listen((position) {
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
        _currentLyricIndex * 40.0,
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
      // Use the repository provider to fetch lyrics
      final repo = ref.read(songRepositoryProvider);
      final lyricsContent = await repo.getLyrics(lyricsUrl);
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
          player.positionStream,
          player.bufferedPositionStream,
          player.durationStream,
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
        stream: player.sequenceStateStream,
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
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onVerticalDragUpdate: (details) {
                          if (details.primaryDelta! < -5) {
                            if (!_showLyrics && metadata.extras?['lyricsUrl'] != null) {
                              _toggleLyrics(metadata.extras!['lyricsUrl'] as String);
                            }
                          } else if (details.primaryDelta! > 5) {
                            if (_showLyrics) {
                              setState(() => _showLyrics = false);
                            }
                          }
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: !_showLyrics
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: metadata.artUri.toString(),
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 100),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
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
                      );
                    }
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
                    onSeek: player.seek,
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Shuffle
                  StreamBuilder<bool>(
                    stream: player.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final shuffleModeEnabled = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(Icons.shuffle, color: shuffleModeEnabled ? Colors.deepPurple : Colors.white),
                        onPressed: () => player.setShuffleModeEnabled(!shuffleModeEnabled),
                      );
                    },
                  ),
                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 36),
                    onPressed: () {
                      if (player.position.inSeconds > 3) {
                        player.seek(Duration.zero);
                      } else {
                        player.seekToPrevious();
                      }
                    },
                  ),
                  // Play/Pause
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? false;
                      return IconButton(
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 72),
                        onPressed: playing ? player.pause : player.play,
                      );
                    },
                  ),
                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 36),
                    onPressed: player.hasNext ? player.seekToNext : null,
                  ),
                  // Repeat
                  StreamBuilder<LoopMode>(
                    stream: player.loopModeStream,
                    builder: (context, snapshot) {
                      final loopMode = snapshot.data ?? LoopMode.off;
                      IconData iconData = Icons.repeat;
                      Color color = Colors.white;
                      if (loopMode == LoopMode.one) {
                        iconData = Icons.repeat_one;
                        color = Colors.deepPurple;
                      } else if (loopMode == LoopMode.all) {
                        iconData = Icons.repeat;
                        color = Colors.deepPurple;
                      }
                      return IconButton(
                        icon: Icon(iconData, color: color),
                        onPressed: () {
                          final nextMode = LoopMode.values[(loopMode.index + 1) % LoopMode.values.length];
                          player.setLoopMode(nextMode);
                        },
                      );
                    },
                  ),
                  // Favorite
                  Consumer(
                    builder: (context, ref, child) {
                      final userData = ref.watch(userDataProvider);
                      final isFavorite = metadata != null && userData.favorites.contains(metadata.id);
                      return IconButton(
                        icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                        color: isFavorite ? Colors.red : Colors.white,
                        onPressed: () {
                          if (metadata != null) {
                            ref.read(userDataProvider.notifier).toggleFavorite(metadata.id);
                          }
                        },
                      );
                    },
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

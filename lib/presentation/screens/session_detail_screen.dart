import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/play_session.dart';
import '../../providers/providers.dart';
import 'player_screen.dart';

class SessionDetailScreen extends ConsumerWidget {
  final PlaySession session;

  const SessionDetailScreen({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final events = session.events ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSessionHeader(context, colorScheme),
          if (events.isNotEmpty)
            _buildSongsHeader(context, events.length, colorScheme),
          Expanded(
            child: events.isEmpty
                ? _buildNoSongsState(colorScheme)
                : _buildSongsList(ref, events, colorScheme),
          ),
          if (events.isNotEmpty)
            _buildRepeatQueueButton(context, ref, events, colorScheme),
        ],
      ),
    );
  }

  Widget _buildSessionHeader(BuildContext context, ColorScheme colorScheme) {
    final startTime = session.startDateTime;
    final timeStr =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.access_time_filled,
                  size: 32,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayDate,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Started at $timeStr',
                      style: TextStyle(
                        fontSize: 15,
                        color: colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                icon: Icons.music_note,
                value: '${session.songCount}',
                label: session.songCount == 1 ? 'Song' : 'Songs',
                colorScheme: colorScheme,
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
              ),
              _buildStatItem(
                context,
                icon: Icons.timer,
                value: session.formattedDuration,
                label: 'Duration',
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSongsHeader(
      BuildContext context, int count, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
            'Songs Played',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSongsState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_off_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No songs recorded',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsList(
      WidgetRef ref, List<SessionEvent> events, ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _buildSongItem(ref, events, context, event, index, colorScheme);
      },
    );
  }

  Widget _buildSongItem(
      WidgetRef ref,
      List<SessionEvent> events,
      BuildContext context,
      SessionEvent event,
      int index,
      ColorScheme colorScheme) {
    final song = event.song;
    final timeStr =
        '${event.dateTime.hour.toString().padLeft(2, '0')}:${event.dateTime.minute.toString().padLeft(2, '0')}';

    IconData statusIcon;
    Color statusColor;
    if (event.isCompleted) {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    } else if (event.isSkipped) {
      statusIcon = Icons.skip_next;
      statusColor = Colors.orange;
    } else {
      statusIcon = Icons.play_circle_filled;
      statusColor = colorScheme.primary;
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        onTap: () {
          if (song != null) {
            final allSongs = events
                .where((e) => e.song != null)
                .map((e) => e.song!)
                .toList();
            ref.read(audioPlayerManagerProvider).playSong(
                  song,
                  contextQueue: allSongs,
                  playlistId: session.id,
                  forceLinear: true,
                );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        title: Text(
          song?.title ?? _getFileNameWithoutExt(event.songFilename),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          song?.artist ?? 'Unknown Artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
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
                  _formatDuration(event.durationPlayed),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Icon(
              statusIcon,
              color: statusColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatQueueButton(
    BuildContext context,
    WidgetRef ref,
    List<SessionEvent> events,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: FilledButton.icon(
          onPressed: () => _repeatQueue(context, ref, events),
          icon: const Icon(Icons.repeat),
          label: const Text(
            'Repeat Queue',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _repeatQueue(
      BuildContext context, WidgetRef ref, List<SessionEvent> events) async {
    // Get songs from events (in order, oldest to newest)
    final songs =
        events.where((e) => e.song != null).map((e) => e.song!).toList();

    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No songs available to play')),
      );
      return;
    }

    final audioManager = ref.read(audioPlayerManagerProvider);

    // Replace queue - the audio manager will handle skipping the first song
    // if it's currently playing
    await audioManager.replaceQueue(songs,
        playlistId: session.id, forceLinear: true);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Playing ${songs.length} ${songs.length == 1 ? 'song' : 'songs'} from session'),
        action: SnackBarAction(
          label: 'Open Player',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          },
        ),
      ),
    );

    Navigator.pop(context);
  }

  String _getFileNameWithoutExt(String filename) {
    final idx = filename.lastIndexOf('.');
    if (idx == -1) return filename;
    final name = filename.substring(0, idx);
    final sepIdx = name.lastIndexOf('/');
    if (sepIdx == -1) return name;
    return name.substring(sepIdx + 1);
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }
}

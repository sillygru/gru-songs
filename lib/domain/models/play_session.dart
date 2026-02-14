import 'package:equatable/equatable.dart';
import '../../models/song.dart';

/// Represents a play event within a session
class SessionEvent extends Equatable {
  final String songFilename;
  final String eventType; // 'listen', 'complete', 'skip'
  final double timestamp;
  final double durationPlayed;
  final double totalLength;
  final double playRatio;
  final Song? song;

  const SessionEvent({
    required this.songFilename,
    required this.eventType,
    required this.timestamp,
    required this.durationPlayed,
    required this.totalLength,
    required this.playRatio,
    this.song,
  });

  factory SessionEvent.fromDb(Map<String, dynamic> dbEvent, {Song? song}) {
    return SessionEvent(
      songFilename: dbEvent['song_filename'] as String,
      eventType: dbEvent['event_type'] as String? ?? 'listen',
      timestamp: (dbEvent['timestamp'] as num?)?.toDouble() ?? 0,
      durationPlayed: (dbEvent['duration_played'] as num?)?.toDouble() ?? 0,
      totalLength: (dbEvent['total_length'] as num?)?.toDouble() ?? 0,
      playRatio: (dbEvent['play_ratio'] as num?)?.toDouble() ?? 0,
      song: song,
    );
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());

  bool get isCompleted => eventType == 'complete' || playRatio >= 0.9;
  bool get isSkipped => eventType == 'skip' || playRatio < 0.25;

  @override
  List<Object?> get props => [
        songFilename,
        eventType,
        timestamp,
        durationPlayed,
        totalLength,
        playRatio,
        song,
      ];
}

/// Represents a listening session
class PlaySession extends Equatable {
  final String id;
  final double startTime;
  final double endTime;
  final String platform;
  final int songCount;
  final double totalDuration;
  final List<SessionEvent>? events;

  const PlaySession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.platform,
    required this.songCount,
    required this.totalDuration,
    this.events,
  });

  factory PlaySession.fromDb(Map<String, dynamic> dbSession,
      {List<SessionEvent>? events}) {
    return PlaySession(
      id: dbSession['id'] as String,
      startTime: (dbSession['start_time'] as num?)?.toDouble() ?? 0,
      endTime: (dbSession['end_time'] as num?)?.toDouble() ?? 0,
      platform: dbSession['platform'] as String? ?? 'unknown',
      songCount: (dbSession['song_count'] as num?)?.toInt() ?? 0,
      totalDuration: (dbSession['total_duration'] as num?)?.toDouble() ?? 0,
      events: events,
    );
  }

  DateTime get startDateTime =>
      DateTime.fromMillisecondsSinceEpoch((startTime * 1000).toInt());

  DateTime get endDateTime =>
      DateTime.fromMillisecondsSinceEpoch((endTime * 1000).toInt());

  Duration get duration =>
      Duration(milliseconds: ((endTime - startTime) * 1000).toInt());

  String get formattedDuration {
    final mins = duration.inMinutes;
    if (mins < 60) {
      return '${mins}m';
    }
    final hours = mins ~/ 60;
    final remainingMins = mins % 60;
    return remainingMins > 0 ? '${hours}h ${remainingMins}m' : '${hours}h';
  }

  /// Groups Today, Yesterday, or returns formatted date
  String get displayDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sessionDate = DateTime(
      startDateTime.year,
      startDateTime.month,
      startDateTime.day,
    );

    if (sessionDate == today) return 'Today';
    if (sessionDate == yesterday) return 'Yesterday';

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
    return '${months[startDateTime.month - 1]} ${startDateTime.day}, ${startDateTime.year}';
  }

  /// Returns just the date portion for grouping
  String get dateKey {
    return '${startDateTime.year}-${startDateTime.month.toString().padLeft(2, '0')}-${startDateTime.day.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        id,
        startTime,
        endTime,
        platform,
        songCount,
        totalDuration,
        events,
      ];
}

/// Helper class to group sessions by date category
class SessionGroup {
  final String label; // "Today", "Yesterday", or formatted date
  final String dateKey; // For sorting
  final List<PlaySession> sessions;

  const SessionGroup({
    required this.label,
    required this.dateKey,
    required this.sessions,
  });
}

/// Extension to group sessions
extension SessionListExtensions on List<PlaySession> {
  List<SessionGroup> groupByDate() {
    final groups = <String, List<PlaySession>>{};

    for (final session in this) {
      groups.putIfAbsent(session.dateKey, () => []).add(session);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Newest first

    return sortedKeys.map((key) {
      final sessions = groups[key]!;
      final firstSession = sessions.first;
      return SessionGroup(
        label: firstSession.displayDate,
        dateKey: key,
        sessions: sessions,
      );
    }).toList();
  }
}

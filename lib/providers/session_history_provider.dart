import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../domain/models/play_session.dart';

/// Provider for loading all play sessions
final sessionHistoryProvider = FutureProvider<List<PlaySession>>((ref) async {
  final dbSessions =
      await DatabaseService.instance.getPlaySessions(minDurationSeconds: 30);

  // Get all songs to match with session events
  final songs = await DatabaseService.instance.getAllSongs();
  final songMap = {for (var s in songs) s.filename: s};

  final sessions = <PlaySession>[];

  for (final dbSession in dbSessions) {
    final session = PlaySession.fromDb(dbSession);

    // Load events for this session
    final dbEvents =
        await DatabaseService.instance.getPlayEventsForSession(session.id);
    final events = dbEvents.map((e) {
      final filename = e['song_filename'] as String;
      final song = songMap[filename];
      return SessionEvent.fromDb(e, song: song);
    }).toList();

    sessions.add(PlaySession(
      id: session.id,
      startTime: session.startTime,
      endTime: session.endTime,
      platform: session.platform,
      songCount: session.songCount,
      totalDuration: session.totalDuration,
      events: events,
    ));
  }

  return sessions;
});

/// Provider for a specific session's details
final sessionDetailProvider =
    FutureProvider.family<PlaySession?, String>((ref, sessionId) async {
  final sessionsAsync = await ref.watch(sessionHistoryProvider.future);
  try {
    return sessionsAsync.firstWhere((s) => s.id == sessionId);
  } catch (_) {
    return null;
  }
});
